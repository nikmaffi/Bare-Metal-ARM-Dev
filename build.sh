#!/usr/bin/env bash
# Build vanilla di TF-A, OP-TEE, U-Boot (R5 + A53) e Linux per BeaglePlay (AM625 GP).
# Uso:  ./build.sh [fetch|tfa|optee|uboot-r5|uboot-a53|linux|modules-install DIR|collect|all]
# Compilatore: TOOLCHAIN=llvm (default, clang) oppure TOOLCHAIN=gcc, anche per singolo passo:
#   TOOLCHAIN=gcc ./build.sh uboot-r5
# Eccezione: U-Boot A53 usa gcc di default (TOOLCHAIN_A53). Con clang 23 l'SPL A53 non
# stampa nulla dopo OP-TEE (provato sulla scheda il 2026-11-06). Per riprovare clang:
#   TOOLCHAIN_A53=llvm ./build.sh uboot-a53
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
JOBS="$(nproc)"
TOOLCHAIN="${TOOLCHAIN:-llvm}"
TOOLCHAIN_A53="${TOOLCHAIN_A53:-gcc}"

# Con clang questi prefissi servono solo come target triple e per le binutils GNU (U-Boot)
export CC32=arm-none-eabi-
export CC64=aarch64-linux-gnu-
export LNX_FW_PATH="$ROOT/ti-linux-firmware"
export TFA_PATH="$ROOT/trusted-firmware-a"
export OPTEE_PATH="$ROOT/optee_os"
UBOOT_PATH="$ROOT/u-boot"
LINUX_PATH="$ROOT/linux"
OUT="$ROOT/out"

TFA_BOARD=lite

fetch() {
	cd "$ROOT"
	[ -d u-boot ] || git clone https://git.u-boot-project.org/u-boot/u-boot.git
	[ -d trusted-firmware-a ] || git clone --depth 1 https://git.trustedfirmware.org/TF-A/trusted-firmware-a.git
	[ -d optee_os ] || git clone --depth 1 https://github.com/OP-TEE/optee_os.git
	[ -d ti-linux-firmware ] || git clone --depth 1 -b ti-linux-firmware https://github.com/TexasInstruments/ti-linux-firmware.git
	[ -d linux ] || git clone --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
}

tfa() {
	cd "$TFA_PATH"
	if [ "$TOOLCHAIN" = llvm ]; then
		# TF-A docs: "CROSS_COMPILE need not be set for Clang"
		# K3 usa ENABLE_PIE=1: la tabella errata in .rodata richiede rilocazioni in
		# sezioni RO, che ld.lld rifiuta di default (GNU ld le accetta in silenzio).
		# -z notext le permette; BL31 le applica da se' all'avvio (fixup_gdt_reloc).
		make -j"$JOBS" CC=clang LDFLAGS="-z notext" ARCH=aarch64 PLAT=k3 SPD=opteed \
			TARGET_BOARD=$TFA_BOARD
	else
		make -j"$JOBS" CROSS_COMPILE=$CC64 ARCH=aarch64 PLAT=k3 SPD=opteed TARGET_BOARD=$TFA_BOARD
	fi
}

optee() {
	cd "$OPTEE_PATH"
	local cc=()
	[ "$TOOLCHAIN" = llvm ] && cc=(COMPILER=clang)
	# Solo TA a 64 bit: niente toolchain arm-linux-gnueabihf.
	# Con COMPILER=clang, CROSS_COMPILE64 serve solo a ricavare --target (mk/clang.mk)
	make -j"$JOBS" "${cc[@]}" CROSS_COMPILE64=$CC64 CFG_ARM64_core=y CFG_USER_TA_TARGETS=ta_arm64 \
		PLATFORM=k3-am62x
}

uboot_make() {
	local build="$1" cross="$2"; shift 2
	cd "$UBOOT_PATH"
	if [ "$TOOLCHAIN" = llvm ]; then
		# U-Boot doc/build/clang.rst: CC=clang, CROSS_COMPILE da' target e binutils GNU.
		# -Wno-multilib-not-found: con arm-none-eabi clang avvisa sempre; i test cc-option
		#   di U-Boot usano -Werror e scarterebbero in silenzio flag come -mabi=aapcs-linux
		#   (risultato: __aeabi_memclr8 non definito al link).
		# -Wno-deprecated-non-prototype: zlib usa definizioni K&R, errore di default in clang recenti.
		make HOSTCC=clang CC="clang -Wno-multilib-not-found" CROSS_COMPILE=$cross O="$build" \
			KCFLAGS=-Wno-deprecated-non-prototype "$@"
	else
		make CROSS_COMPILE=$cross O="$build" "$@"
	fi
}

uboot_r5() {
	uboot_make build-r5 $CC32 am62x_beagleplay_r5_defconfig
	uboot_make build-r5 $CC32 -j"$JOBS" BINMAN_INDIRS="$LNX_FW_PATH"
}

uboot_a53() {
	local TOOLCHAIN="$TOOLCHAIN_A53"
	uboot_make build-a53 $CC64 am62x_beagleplay_a53_defconfig
	uboot_make build-a53 $CC64 -j"$JOBS" BINMAN_INDIRS="$LNX_FW_PATH" \
		BL31="$TFA_PATH/build/k3/$TFA_BOARD/release/bl31.bin" \
		TEE="$OPTEE_PATH/out/arm-plat-k3/core/tee-raw.bin"
}

linux_make() {
	cd "$LINUX_PATH"
	if [ "$TOOLCHAIN" = llvm ]; then
		make ARCH=arm64 LLVM=1 "$@"
	else
		make ARCH=arm64 CROSS_COMPILE=$CC64 "$@"
	fi
}

linux() {
	linux_make defconfig
	# Senza initrd: TI SCI (clock, power domain, IRQ dei periferici K3) deve essere
	# built-in, altrimenti il controller SD resta in deferred probe e il rootfs non si monta.
	./scripts/config --enable TI_SCI_PROTOCOL --enable TI_SCI_CLK \
		--enable TI_SCI_PM_DOMAINS --enable TI_SCI_INTR_IRQCHIP \
		--enable TI_SCI_INTA_IRQCHIP --enable RESET_TI_SCI
	linux_make olddefconfig
	linux_make -j"$JOBS" Image dtbs modules
}

modules_install() {
	local dest="${1:?serve il punto di mount del rootfs, es. /mnt/rootfs}"
	linux_make INSTALL_MOD_PATH="$dest" modules_install
}

collect() {
	mkdir -p "$OUT/boot"
	# La BeaglePlay monta un AM625 di tipo GP: si usa l'immagine -gp-
	cp -L "$UBOOT_PATH/build-r5/tiboot3-am62x-gp-evm.bin" "$OUT/boot/tiboot3.bin"
	cp -L "$UBOOT_PATH/build-a53/tispl.bin" "$OUT/boot/tispl.bin"
	cp -L "$UBOOT_PATH/build-a53/u-boot.img" "$OUT/boot/u-boot.img"
	cat > "$OUT/boot/uEnv.txt" <<-'EOF'
	# Letto da U-Boot vanilla (envboot di include/env/ti/mmc.env) prima di extlinux.
	# Servono a booti per il kernel compresso Image.gz della Debian
	# (doc/develop/distro.rst). Il kernel viene decompresso a 0xa0000000,
	# sopra OP-TEE (0x9e800000-0xa0000000), poi spostato a kernel_addr_r.
	kernel_comp_addr_r=0xa0000000
	kernel_comp_size=0x4000000
	EOF
	if [ -f "$LINUX_PATH/arch/arm64/boot/Image" ]; then
		cp "$LINUX_PATH/arch/arm64/boot/Image" "$OUT/boot/Image-vanilla"
		cp "$LINUX_PATH/arch/arm64/boot/dts/ti/k3-am625-beagleplay.dtb" "$OUT/boot/k3-am625-beagleplay-vanilla.dtb"
	fi
	ls -l "$OUT/boot"
}

case "${1:-all}" in
	fetch)           fetch ;;
	tfa)             tfa ;;
	optee)           optee ;;
	uboot-r5)        uboot_r5 ;;
	uboot-a53)       uboot_a53 ;;
	linux)           linux ;;
	modules-install) modules_install "${2:-}" ;;
	collect)         collect ;;
	all)             fetch; tfa; optee; uboot_r5; uboot_a53; collect; linux; collect ;;
	*) echo "uso: $0 [fetch|tfa|optee|uboot-r5|uboot-a53|linux|modules-install DIR|collect|all]"; exit 1 ;;
esac
