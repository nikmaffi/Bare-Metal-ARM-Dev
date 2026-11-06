# 1 – Boot di U-Boot e Linux vanilla su BeaglePlay (tutto da microSD, build con LLVM/clang)

Requisito: **U-Boot e kernel Linux vanilla** (mainline), non quelli BeagleBoard/TI.
Il rootfs non è oggetto del requisito: si riusa quello Debian ufficiale.

Strategia: **un pezzo alla volta**, tutto su microSD. L'eMMC non si tocca e resta
come riserva, con Debian e U-Boot 2021.01 di fabbrica.

0. Scrivo la Debian ufficiale su microSD e verifico che parta **dalla SD** — *fatto*
1. Sostituisco **solo U-Boot** sulla SD → verifico che Debian parta ancora — *fatto il 2026-11-06*
2. Sostituisco **solo il kernel** (Linux mainline) → rootfs Debian invariato — *da fare*

Lo stato dettagliato e i problemi risolti sono in [2-rapporto-build-vanilla.md](2-rapporto-build-vanilla.md).

La scheda non si "brickka": se qualcosa va storto basta riscrivere la SD.

## Catena di boot (AM625, famiglia TI K3)

| File          | Gira su | Contiene                                              |
|---------------|---------|-------------------------------------------------------|
| `tiboot3.bin` | R5      | U-Boot SPL R5 + firmware TIFS (sicurezza) + config board |
| `tispl.bin`   | A53     | TF-A (BL31) + OP-TEE (BL32) + firmware DM + U-Boot SPL A53 |
| `u-boot.img`  | A53     | U-Boot vero e proprio + device tree                   |

Per questo servono due target: ARMv7 32 bit (R5) e AArch64 (A53).
Dal log del primo avvio il SoC è `AM62X SR1.0 GP` → si usa `tiboot3-am62x-gp-evm.bin`.
I firmware TI (TIFS, DM) sono binari chiusi da `ti-linux-firmware`: li richiede
anche l'U-Boot mainline e non hanno alternative.

**Pulsante USR**: tenuto premuto all'accensione → la ROM avvia dalla **SD**.
Senza USR → avvia dall'**eMMC**, cioè dal vecchio U-Boot 2021.01. Va tenuto
premuto **a ogni accensione**.

## 1. Dipendenze host (EndeavourOS/Arch)

```bash
sudo pacman -S --needed clang lld llvm \
    aarch64-linux-gnu-binutils arm-none-eabi-binutils \
    base-devel git bc bison flex dtc swig openssl gnutls util-linux libelf pahole \
    python-pyelftools python-yaml python-jsonschema yamllint python-cryptography \
    python-setuptools uboot-tools cpio xz
```

Supporto clang dei vari componenti:

| Componente | Clang | Come lo usa lo script |
|---|---|---|
| Linux | supportato ufficialmente | `make ARCH=arm64 LLVM=1` (solo strumenti LLVM, `CROSS_COMPILE` non serve) |
| TF-A | supportato (min. Clang 18.1.8) | `make CC=clang` (`CROSS_COMPILE` non serve) |
| OP-TEE | supportato (`COMPILER=clang`) | usa ld.lld e llvm-*. `CROSS_COMPILE64` serve solo per `--target` |
| U-Boot | supporto parziale | `CC=clang`, ma assembler e linker sono le **binutils GNU** indicate da `CROSS_COMPILE` |

Le binutils GNU (`aarch64-linux-gnu-binutils`, `arm-none-eabi-binutils`) servono
**solo a U-Boot**: la sua documentazione (doc/build/clang.rst) usa `$(CROSS_COMPILE)as`
e non l'assembler integrato di LLVM. Gcc non viene usato.

La documentazione U-Boot su clang non cita le schede K3 né l'R5. Se una build
U-Boot fallisce con clang, si può ripiegare su gcc **solo per quel passo**:
```bash
sudo pacman -S --needed aarch64-linux-gnu-gcc arm-none-eabi-gcc arm-none-eabi-newlib
TOOLCHAIN=gcc ./build.sh uboot-r5
```

## 2. Build

Lo script [build.sh](build.sh) segue la sezione "Build procedure" di
`u-boot/doc/board/beagle/am62x_beagleplay.rst`. I sorgenti stanno accanto a `u-boot/`.
Di default usa `TOOLCHAIN=llvm`. Fa eccezione U-Boot A53, che usa gcc (`TOOLCHAIN_A53=gcc`):
compilato con clang 23 si blocca sulla scheda subito dopo OP-TEE (vedi "Problemi probabili").

```bash
cd ~/Scrivania/TESI/Bare-Metal-ARM-Dev
./build.sh fetch       # clona TF-A, OP-TEE, ti-linux-firmware, linux
./build.sh tfa         # -> trusted-firmware-a/build/k3/lite/release/bl31.bin
./build.sh optee       # -> optee_os/out/arm-plat-k3/core/tee-raw.bin
./build.sh uboot-r5    # -> u-boot/build-r5/tiboot3-am62x-gp-evm.bin
./build.sh uboot-a53   # -> u-boot/build-a53/tispl.bin, u-boot.img (con gcc, vedi sotto)
./build.sh collect     # copia i 3 file di boot in out/boot/ e genera uEnv.txt
./build.sh linux       # kernel mainline, defconfig arm64 (ci mette un po')
./build.sh collect     # aggiunge Image-vanilla e il dtb
```

L'ordine conta: l'A53 ingloba BL31 e OP-TEE, quindi vanno compilati prima.
Conviene lanciare i passi uno alla volta, così si vede subito quale fallisce.
Dopo un cambio di toolchain conviene ripulire (`make O=build-r5 distclean`, ecc.).

## 3. Preparare la microSD con la Debian ufficiale

Immagini: https://www.beagleboard.org/distros (oppure con BeagleBoard Imaging Utility).
Scegliere una **BeaglePlay Debian IoT** (minimal, senza desktop). Il nome del file
indica la SD minima (es. `...-10gb.img.xz`). Qui si usa una microSD da 32 GB.

```bash
# scaricare .img.xz e il relativo .sha256sum, poi:
sha256sum -c beagleplay-debian-*.img.xz.sha256sum
xz -l beagleplay-debian-*.img.xz            # "Uncompressed" deve stare nella SD
lsblk                                       # individuare la SD, es. /dev/sdX — ATTENZIONE al disco giusto
xzcat beagleplay-debian-*.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
lsblk -f /dev/sdX                           # annotare le partizioni: FAT (BOOT) ed ext4 (rootfs)
```

Immagine scelta (2026-11-06): `beagleplay-debian-13.7-iot-v6.18-k3-arm64-2026-09-20-10gb.img.xz`,
con SHA256 `47f6e613b84bc6570fef8442e0fff9bcf64f0324eb906628ec8ea6aec82acb6e`. Contiene U-Boot `v2026.07-Beagle` e un kernel BeagleBoard 6.18, entrambi da
sostituire.
**Prima del primo avvio** la pagina ufficiale dice: *"set your user password in the
sysconf.txt file located in the fat32 partition"*. Quindi va montata la partizione FAT e
modificato `sysconf.txt` (non contare su `debian:temppwd`).

Primo test (senza cambiare nulla): SD inserita, `picocom -b 115200 /dev/ttyUSB0`,
**USR premuto** all'accensione, rilasciare quando si accende il LED di alimentazione.
Dal log deve risultare un avvio dalla SD (non `MMC: no card present` come in
`0-primo-avvio.md`, che era un boot da eMMC). Sulla scheda:
```bash
cat /proc/cmdline       # annotare il root= usato
lsblk                   # la SD con il DT mainline è mmcblk1
```

## 4. Installare U-Boot vanilla sulla SD (tutto dal PC)

Si sostituiscono i tre file di boot nella partizione FAT della SD: `tiboot3.bin`,
`tispl.bin` e `u-boot.img`. Si aggiunge anche `uEnv.txt`, senza il quale U-Boot vanilla
non avvia il kernel Debian (vedi 4.5). Il resto della SD, cioè `extlinux/`, il kernel Debian e il
rootfs, **non si tocca**. Al termine U-Boot è vanilla, mentre il kernel è ancora quello
Debian, che si sostituisce al passo 5.

Prerequisiti: `./build.sh collect` ha già riempito `out/boot/` e la Debian della SD è
partita almeno una volta (passo 3).

### 4.1 Spegnere la scheda ed estrarre la SD

Spegnere in modo pulito, per non corrompere la SD, poi staccare il cavo USB-C:
- da login seriale: `sudo poweroff` sulla scheda;
- in alternativa: tenere premuto il tasto POWER finché il LED non si spegne.

Poi estrarre la microSD e inserirla nel PC.

### 4.2 Individuare la SD sul PC

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS,TRAN
```

La SD è il disco da circa **29.7G**, con tre partizioni:

| Partizione | Dimensione | Tipo | Contenuto |
|------------|-----------:|------|-----------|
| 1 | 256M | `vfat` | boot |
| 2 | 2G | `swap` | swap |
| 3 | 27.5G | `ext4` | rootfs |

Il nome cambia in base al lettore:

| Lettore | Disco | Partizione FAT |
|---------|-------|----------------|
| USB | `/dev/sdb` (o `sdc`…) | `/dev/sdb1` |
| Integrato | `/dev/mmcblk0` | `/dev/mmcblk0p1` |

**Attenzione a non confondere i dischi del PC** (`nvme0n1`, `sda` …).

Annotare la partizione FAT in una variabile: tutti i comandi successivi la usano.

```bash
BOOTPART=/dev/sdb1          # <-- SOSTITUIRE con la partizione vfat da 256M vista sopra
lsblk -o NAME,SIZE,FSTYPE $BOOTPART   # controllo: deve dire 256M vfat
```

Se il desktop ha montato la SD da solo (`MOUNTPOINTS` non vuoto), smontarla:
`sudo umount $BOOTPART`.

### 4.3 Montare la partizione FAT e controllarla

```bash
cd ~/Scrivania/TESI/Bare-Metal-ARM-Dev
sudo mkdir -p /mnt/boot
sudo mount $BOOTPART /mnt/boot
ls -l /mnt/boot              # devono esserci tiboot3.bin, tispl.bin, u-boot.img, extlinux/, sysconf.txt
```

Se i tre file non ci sono o hanno nomi diversi, **fermarsi** e controllare.

### 4.4 Backup dei file originali (sul PC)

Il backup va sul PC, così resta disponibile anche se la SD non si avvia più.

```bash
mkdir -p backup/sd-boot-2026.07
cp /mnt/boot/{tiboot3.bin,tispl.bin,u-boot.img} backup/sd-boot-2026.07/
cp -r /mnt/boot/extlinux backup/sd-boot-2026.07/      # utile per il passo 5
ls -l backup/sd-boot-2026.07/
```

`backup/` è nel `.gitignore`.

### 4.5 Copiare i file vanilla e verificarli

`uEnv.txt` serve perché la Debian avvia un kernel compresso (`/Image.gz`). Per
decomprimerlo, `booti` vuole le variabili `kernel_comp_addr_r` e `kernel_comp_size`
(`doc/develop/distro.rst`). L'U-Boot BeagleBoard le ha già, quello vanilla no. Senza
queste variabili il log mostra `kernel_comp_addr_r or kernel_comp_size is not provided!`.
U-Boot vanilla legge `uEnv.txt` dalla FAT prima di extlinux (`envboot` in
`include/env/ti/mmc.env`).

```bash
sudo cp out/boot/{tiboot3.bin,tispl.bin,u-boot.img,uEnv.txt} /mnt/boot/
sync
sha256sum out/boot/{tiboot3.bin,tispl.bin,u-boot.img,uEnv.txt} /mnt/boot/{tiboot3.bin,tispl.bin,u-boot.img,uEnv.txt}
# gli hash devono coincidere a coppie (out/boot/X == /mnt/boot/X)
strings /mnt/boot/u-boot.img | grep -m1 'U-Boot 20'   # deve dire U-Boot 2026.10-...
```

### 4.6 Smontare ed estrarre

```bash
sudo umount /mnt/boot
sudo eject ${BOOTPART%[0-9]}   # per /dev/sdb1 → /dev/sdb (con mmcblk0p1 usare: sudo eject /dev/mmcblk0)
```

### 4.7 Avviare la scheda

1. Inserire la SD nella BeaglePlay e aprire la seriale sul PC con
   `picocom -b 115200 /dev/ttyUSB0`.
2. **Tenere premuto USR**, poi collegare l'USB-C. Rilasciare USR dopo 2–3 secondi.
3. Leggere la **prima riga** sulla seriale:

| Prima riga | Significato |
|------------|-------------|
| `U-Boot SPL 2026.10-00667-g0a55b098d6f5 (Nov 06 2026 ...)` | **riuscito**: è il tuo U-Boot vanilla |
| `U-Boot SPL 2026.07-g497fcbd50a6b` | i file non sono stati sostituiti (rifare 4.3–4.5) |
| `U-Boot SPL 2021.01-gb248392d` | è partito dall'eMMC: USR non premuto, riprovare |
| nulla, LED utente `00000` | il nuovo `tiboot3.bin` non parte: vedere 4.8 |

Sequenza attesa, verificata sulla scheda il 2026-11-06 (log abbreviato):

```
U-Boot SPL 2026.10-00667-g0a55b098d6f5 (Nov 06 2026 - 11:45:52 +0100)   <- SPL R5 (clang)
Trying to boot from MMC2
Starting ATF on ARM64 core...
NOTICE:  BL31: v2.15.0(release):6da12e7
I/TC: OP-TEE version: cde9355 (clang version 23.1.4) ...
I/TC: Disabling output console                                           <- normale
U-Boot SPL 2026.10-00667-g0a55b098d6f5 (Nov 06 2026 - 14:57:02 +0100)   <- SPL A53 (gcc)
U-Boot 2026.10-00667-g0a55b098d6f5 (Nov 06 2026 - 14:57:02 +0100)       <- U-Boot vanilla
SoC:   AM62X SR1.0 GP
Loaded env from uEnv.txt
** Booting bootflow 'mmc@fa00000.bootdev.part_1' with extlinux          <- SD
Retrieving file: /Image.gz
   Uncompressing Kernel Image to 0
Starting kernel ...
Debian GNU/Linux 13 beagleplay ttyS2
beagleplay login:
```

Le due righe `U-Boot SPL` hanno date diverse perché R5 e A53 sono due build separate.

- **Manca la seconda riga `U-Boot SPL` e la scheda resta muta**: `tispl.bin` è stato
  compilato con clang. Ricompilare con `./build.sh uboot-a53` (gcc) e `./build.sh collect`.
- **Manca `Loaded env from uEnv.txt`** (`Failed to load 'uEnv.txt'`): `uEnv.txt` non è
  sulla FAT. Il kernel Debian non parte e U-Boot ripiega sull'eMMC (vedi 4.8).

Il kernel resta quello Debian 6.18: si cambia al passo 5. Salvare il log seriale negli
appunti come prova.

LED utente: `00000` = R5 non partito, `11111` = U-Boot A53 partito,
`10101` = avvio OS, `01010` = OS fallito → shell U-Boot.

### 4.8 Se non parte: ripristino (dal PC)

L'eMMC non è stata toccata: accendendo **senza** USR la scheda riparte normalmente.

Se il kernel della SD non parte, U-Boot vanilla passa da solo all'eMMC
(`Scanning bootdev 'mmc@fa10000.bootdev'`, voce `Linux eMMC`). Avvia così il kernel di
fabbrica con il device tree sbagliato: ripete all'infinito `am65-cpsw-nuss ... error
retrieving port phy: -517` e non arriva al login. Non è un guasto: spegnere tenendo
premuto POWER e correggere la SD dal PC.

Per rimettere a posto la SD:

1. Rimettere la SD nel PC.
2. Ripetere 4.2 e 4.3 per ritrovare `BOOTPART` e montare `/mnt/boot`.
3. Ripristinare i file originali:

```bash
sudo cp backup/sd-boot-2026.07/{tiboot3.bin,tispl.bin,u-boot.img} /mnt/boot/
sudo rm -f /mnt/boot/uEnv.txt      # non c'era nella Debian originale
sync && sudo umount /mnt/boot
```

4. Mandare il log seriale per l'analisi.

Un'alternativa, se il problema è il codice generato da clang, è ricompilare solo U-Boot
con `TOOLCHAIN=gcc ./build.sh uboot-r5` (o `uboot-a53`), poi `./build.sh collect` e
ripetere da 4.1.

## 5. Installare Linux vanilla

Si aggiunge una voce nuova a `extlinux.conf`, lasciando quella Debian come riserva.

```bash
# SD nel PC, BOOTPART come al passo 4.2; ROOTPART = la partizione ext4 da 27.5G
ROOTPART=/dev/sdb3          # <-- SOSTITUIRE (lettore integrato: /dev/mmcblk0p3)
sudo mkdir -p /mnt/boot /mnt/rootfs
sudo mount $BOOTPART /mnt/boot
sudo mount $ROOTPART /mnt/rootfs
sudo cp out/boot/Image-vanilla out/boot/k3-am625-beagleplay-vanilla.dtb /mnt/boot/
sudo ./build.sh modules-install /mnt/rootfs   # stessa toolchain della build (LLVM=1)
cat /mnt/boot/extlinux/extlinux.conf   # vedere il formato della voce esistente
```

Aggiungere a `/mnt/boot/extlinux/extlinux.conf` (e impostare `default vanilla`):

```
label vanilla
    kernel /Image-vanilla
    fdt /k3-am625-beagleplay-vanilla.dtb
    append console=ttyS2,115200n8 earlycon root=/dev/mmcblk1p3 rw rootfstype=ext4 rootwait
```

- `p3`: con la Debian 13.7 IoT il rootfs è la partizione 3 (dal log di boot: `root=/dev/mmcblk1p3`,
  swap in `p2`). Se si usa un'altra immagine, verificarlo. In alternativa `root=PARTUUID=...`
  letto con `sudo blkid $ROOTPART`, che non dipende dalla numerazione.
- Niente `initrd`: con `defconfig` i driver SD (`sdhci-am654`) ed ext4 sono built-in.
- Se il file usa percorsi relativi a una sottocartella (es. `/boot/...`), adeguare `kernel`/`fdt`.

```bash
sync && sudo umount /mnt/boot /mnt/rootfs
```

Successo: `uname -a` e `cat /proc/version` sulla scheda mostrano la versione
mainline e `clang version 23...`. Salvare questi output (e il banner U-Boot)
negli appunti come prova per la tesi.

## Problemi probabili

- **TF-A con ld.lld: `relocation R_AARCH64_ABS64 cannot be used against local symbol`**
  (risolto in build.sh). K3 compila BL31 come PIE (`ENABLE_PIE := 1` in
  `plat/ti/common/plat_common.mk`), e la tabella errata in `.rodata` contiene indirizzi
  assoluti. GNU ld accetta in silenzio queste rilocazioni in una sezione RO (TEXTREL),
  ld.lld no. Lo script passa `LDFLAGS="-z notext"`. In entrambi i casi l'ELF contiene
  solo `R_AARCH64_RELATIVE`, che BL31 applica all'avvio (`fixup_gdt_reloc`,
  `lib/aarch64/misc_helpers.S`). Alternativa: `LD=aarch64-linux-gnu-ld` (clang + linker GNU).
- **U-Boot R5 con clang: `undefined reference to __aeabi_memclr8`** (risolto in build.sh).
  Con `--target=arm-none-eabi` clang emette sempre `warning: no multilib structure`.
  I test `cc-option` di U-Boot compilano con `-Werror`, quindi falliscono tutti, e flag
  come `-mabi=aapcs-linux` vengono scartati in silenzio. Senza quel flag
  `arch/arm/lib/eabi_compat.c` non si compila. Lo script usa
  `CC="clang -Wno-multilib-not-found"`. Controllo: `grep -o -- -mabi=aapcs-linux
  u-boot/build-r5/common/.board_f.o.cmd`.
- **U-Boot con clang: `lib/zlib/inffast.c ... -Wdeprecated-non-prototype`**: zlib usa
  definizioni K&R. Lo script passa `KCFLAGS=-Wno-deprecated-non-prototype`.
- **binman: `Unknown entry type 'ti-board-config' ... No module named 'yamllint'`**:
  `sudo pacman -S yamllint`.

- **Dopo `I/TC: Disabling output console` non compare più nulla, LED spenti**
  (provato il 2026-11-06). L'SPL R5, BL31 e OP-TEE (tutti clang) funzionano, mentre l'SPL
  A53 compilato con clang 23 non stampa nulla. Gli indirizzi e il contenuto di
  `tispl.bin` (`u-boot/build-a53/tools/dumpimage -l`) sono corretti. Con U-Boot A53
  compilato con gcc, e TF-A/OP-TEE ancora clang, la scheda arriva al prompt di U-Boot.
  Per questo build.sh usa gcc per `uboot-a53`. La causa precisa in clang è ancora da
  indagare.
- **`kernel_comp_addr_r or kernel_comp_size is not provided!` e poi boot dall'eMMC**:
  manca `uEnv.txt` sulla FAT (vedi 4.5).
- **U-Boot non compila con clang** (errori su registro `gd`/`x18`/`r9`, link, SPL
  troppo grande per l'R5): ripiegare su gcc solo per quel passo (vedi §1).
- **Toolchain troppo nuova** (Clang 23 / GCC 16): se TF-A o OP-TEE falliscono per
  warning trattati come errori, riprovare con `E=0` (TF-A) o `WARNS=0` (OP-TEE).
- **Errore binman su firmware mancante**: controllare che `ti-linux-firmware`
  sia sul branch `ti-linux-firmware`.
- **Parte ancora U-Boot 2021.01**: USR non premuto all'accensione (boot da eMMC).
- **Kernel parte ma `VFS: unable to mount root`**: `root=` sbagliato.
- **Nessun output dopo `Starting kernel ...`**: verificare `console=ttyS2,115200n8 earlycon`.
- **Moduli non caricati** (`modprobe` fallisce): `modules-install` non eseguito
  o rootfs sbagliato montato.

## Fonti e verifica (controllato il 2026-11-06)

Dalla documentazione ufficiale:
- Variabili, defconfig, comandi TF-A / OP-TEE / U-Boot R5 e A53, file da copiare
  sulla SD, pulsante USR, LED: U-Boot, `doc/board/beagle/am62x_beagleplay.rst`
  (https://docs.u-boot.org/en/latest/board/beagle/am62x_beagleplay.html) e `doc/board/ti/k3.rst`.
- Sintassi `extlinux.conf` e percorso `/extlinux/extlinux.conf`: U-Boot `doc/develop/distro.rst`.
- U-Boot con clang (`CC=clang`, binutils da `CROSS_COMPILE`): U-Boot `doc/build/clang.rst`.
- `ARCH`, `CROSS_COMPILE`, `INSTALL_MOD_PATH`: https://docs.kernel.org/kbuild/kbuild.html
- `LLVM=1`, niente `CROSS_COMPILE`: https://docs.kernel.org/kbuild/llvm.html
- TF-A con clang (`CC=clang`, Clang ≥ 18.1.8): trustedfirmware-a.readthedocs.io,
  "Prerequisites" e "Performing an Initial Build".
- Immagini Debian BeaglePlay e dimensione minima della SD nel nome file: https://www.beagleboard.org/distros
- Console seriale lato host (`/dev/ttyUSB0`): https://docs.beagleboard.org/boards/beagleplay/demos-and-tutorials/using-serial-console.html

Dai sorgenti, non dalla documentazione:
- Nome `tiboot3-am62x-gp-evm.bin`: `u-boot/arch/arm/dts/k3-am625-r5-beagleplay.dts`.
  `tispl.bin` e `u-boot.img` sono symlink alle versioni `_unsigned` (da qui il `cp -L`).
- OP-TEE `COMPILER=clang`: `optee_os/mk/config.mk` e `mk/clang.mk` (ld.lld, llvm-ar, target
  da `CROSS_COMPILE64`). I builtins vengono da `CFG_LIBUTILS_WITH_COMPILER_RT=y`.
- `console=ttyS2,115200n8`: nel DT `stdout-path = "serial2:115200n8"`, e il log Debian mostra `ttyS2`.
- SD = `mmc1` (`sdhci1`, commento `/* SD/MMC */`): `k3-am625-beagleplay.dts`.
- `sdhci-am654`, ext4, 8250_omap built-in (`=y`): `arch/arm64/configs/defconfig` mainline,
  quindi niente initrd. In U-Boot `initrd` è opzionale (`boot/pxe_utils.c`).

Scelte mie, che si discostano dalla documentazione:
- Toolchain LLVM/clang al posto di gcc (richiesta dell'utente). La doc BeaglePlay usa gcc.
- `arm-none-eabi-` al posto di `arm-linux-gnueabihf-` come prefisso 32 bit (la seconda non è nei repo Arch).
- OP-TEE con `CFG_USER_TA_TARGETS=ta_arm64` e senza `CROSS_COMPILE=$CC32`.
- Build U-Boot con `O=build-r5` / `O=build-a53`, così le due build non si sovrascrivono.
- Kernel mainline con `defconfig` arm64, cross-compilato. La guida BeagleBoard
  (beagleplay-kernel-development) compila invece *sulla scheda*, parte da
  `/proc/config.gz` (o `bb.org_defconfig` del fork BeagleBoard) e installa un `.deb`.
- Workaround `E=0` / `WARNS=0`: ipotesi, non ancora provati.
