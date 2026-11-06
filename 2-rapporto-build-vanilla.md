# 2 – Rapporto: build vanilla di U-Boot e Linux con LLVM/clang

Data: 2026-11-06. Questo documento riassume il lavoro fatto per avviare U-Boot e il
kernel Linux **mainline** sulla BeaglePlay. Racconta le decisioni prese, i problemi
incontrati con la toolchain LLVM e lo stato attuale.

**In breve**: U-Boot vanilla 2026.10 e il kernel mainline `7.4.0-rc1` si avviano dalla
microSD e portano la Debian della SD fino al login. Sulla scheda `uname -r` restituisce
`7.4.0-rc1-gf66469d9905b`. Provato il 2026-11-06.
La procedura passo passo è in [1-boot-vanilla.md](1-boot-vanilla.md); lo script di build è
[build.sh](build.sh).

## Obiettivo e vincoli

- **Vanilla**: U-Boot e kernel Linux presi dai repository ufficiali (mainline), non le
  versioni BeagleBoard o TI SDK. Il rootfs non fa parte del requisito: si riusa la Debian
  ufficiale.
- **Tutto su microSD**: l'eMMC conserva l'installazione di fabbrica (Debian + U-Boot
  2021.01) e resta un sistema di ripiego sempre funzionante.
- **LLVM/clang al posto di gcc** per tutti i componenti. Rimane un ripiego con
  `TOOLCHAIN=gcc` per il singolo passo. U-Boot A53 è passato a gcc dopo la prova sulla
  scheda (problema 5).

## Punto di partenza

- Console seriale funzionante: cavo FTDI 3.3 V, `picocom -b 115200 /dev/ttyUSB0`
  (vedi [0-primo-avvio.md](0-primo-avvio.md)).
- Il primo avvio è stato fatto dall'**eMMC**: U-Boot 2021.01 di fabbrica. Il log mostra
  `SoC: AM62X SR1.0 GP`, cioè un dispositivo GP (non HS-FS). Da questo dipende quale
  immagine `tiboot3` usare.

## Catena di boot dell'AM625

| Fase | Core | File | Contenuto |
|------|------|------|-----------|
| 1 | Cortex-R5 | `tiboot3.bin` | SPL R5 + firmware TIFS + board config |
| 2 | Cortex-A53 | `tispl.bin` | TF-A BL31 + OP-TEE + firmware DM + SPL A53 |
| 3 | Cortex-A53 | `u-boot.img` | U-Boot proper |
| 4 | Cortex-A53 | `Image` + `.dtb` | kernel Linux, avviato tramite `extlinux.conf` |

Per avviare da microSD si tiene premuto il tasto USR all'accensione.

Fonti: documentazione U-Boot `doc/board/beagle/am62x_beagleplay.rst` e
`doc/board/ti/k3.rst`.

## Componenti e versioni

| Componente | Sorgente | Versione usata |
|------------|----------|----------------|
| U-Boot | git.u-boot-project.org | `v2026.10-668-g0a55b098d6f` |
| TF-A | git.trustedfirmware.org | commit `6da12e7` |
| OP-TEE OS | github.com/OP-TEE/optee_os | commit `cde9355` |
| Firmware TI | ti-linux-firmware (branch `ti-linux-firmware`) | commit `b925982` |
| Linux | torvalds/linux (mainline) | ultimo commit clonato |
| Toolchain | Arch / EndeavourOS | clang/lld/llvm 23.1.4 + binutils GNU `arm-none-eabi-`, `aarch64-linux-gnu-` |

Parametri principali:
- **U-Boot**: defconfig `am62x_beagleplay_r5_defconfig` e `am62x_beagleplay_a53_defconfig`.
- **TF-A**: `PLAT=k3 TARGET_BOARD=lite SPD=opteed`.
- **OP-TEE**: `PLATFORM=k3-am62x`.
- **Firmware TI**: passato a binman con `BINMAN_INDIRS`.

## Come si usa clang per ogni componente

| Componente | Modalità | Riferimento |
|------------|----------|-------------|
| Linux | `make ARCH=arm64 LLVM=1` | Documentazione kernel, "Building Linux with Clang/LLVM" |
| TF-A | `CC=clang` (ld.lld), senza `CROSS_COMPILE` | Documentazione TF-A, sezione build options |
| OP-TEE | `COMPILER=clang`, target ricavato da `CROSS_COMPILE64` | `mk/clang.mk` |
| U-Boot R5 | `CC=clang` + binutils GNU da `CROSS_COMPILE` | `doc/build/clang.rst` |
| U-Boot A53 | **gcc** 16.2 (`aarch64-linux-gnu-`): con clang si blocca all'avvio (problema 5) | — |

Per U-Boot la documentazione copre clang in generale, ma **non** la combinazione
K3/R5. Era quindi il passo più a rischio. In pratica l'SPL R5 compilato con clang
funziona, la parte A53 no.

## Problemi incontrati e soluzioni

### 1. TF-A: ld.lld rifiuta le rilocazioni ABS64

```
ld.lld: error: relocation R_AARCH64_ABS64 cannot be used against local symbol; recompile with -fPIC
>>> referenced by cortex_a53.o:(.rodata.errata.errata_entries+0x0)
```

- **Causa**: la piattaforma K3 compila BL31 come eseguibile a posizione indipendente
  (`ENABLE_PIE := 1` in `plat/ti/common/plat_common.mk`). La tabella degli errata della CPU
  sta in `.rodata` e contiene indirizzi assoluti, quindi servono rilocazioni in una sezione
  di sola lettura (TEXTREL). GNU ld le accetta senza segnalarlo, ld.lld di default no.
- **Soluzione**: `LDFLAGS="-z notext"`.
- **Verifica**: con `llvm-readelf -r` l'ELF risultante contiene solo rilocazioni
  `R_AARCH64_RELATIVE`, lo stesso tipo che produce GNU ld. BL31 le applica da solo
  all'avvio (`fixup_gdt_reloc` in `lib/aarch64/misc_helpers.S`).
- **Alternativa provata**: `LD=aarch64-linux-gnu-ld` (clang con il linker GNU).

### 2. U-Boot: zlib non compila con clang 23

```
lib/zlib/inffast.c:50:20: error: a function definition without a prototype is deprecated
in all versions of C and is not supported in C23 [-Werror,-Wdeprecated-non-prototype]
```

- **Causa**: zlib usa ancora definizioni di funzione in stile K&R, che le versioni recenti
  di clang trattano come errore di default. Il codice è corretto in C11 (U-Boot compila con
  `-std=gnu11`).
- **Soluzione**: `KCFLAGS=-Wno-deprecated-non-prototype`.

### 3. U-Boot R5: `undefined reference to __aeabi_memclr8`

Questo è stato il problema più subdolo, perché l'errore compare in un punto lontano dalla
causa.

- **Sintomo**: il link dell'SPL R5 fallisce perché manca `__aeabi_memclr8`, una funzione
  helper dell'ABI ARM.
- **Prima osservazione**: U-Boot definisce quella funzione in
  `arch/arm/lib/eabi_compat.c`. Il file però viene compilato solo se `PLATFORM_CPPFLAGS`
  contiene `-mabi=aapcs-linux` (`arch/arm/config.mk`, `arch/arm/lib/Makefile`).
- **Causa vera**: con `--target=arm-none-eabi`, clang 23 emette a ogni invocazione
  `warning: no multilib structure encoded for Arm, Aarch64 and PPC targets`. La macro
  `cc-option` di U-Boot (`scripts/Makefile.compiler`) prova ogni flag opzionale compilando
  con `-Werror`. Il warning fa quindi fallire **tutte** le prove, e i flag opzionali
  vengono scartati senza alcun messaggio, compreso `-mabi=aapcs-linux`.
- **Soluzione**: `CC="clang -Wno-multilib-not-found"`.
- **Verifica**: `-mabi=aapcs-linux` compare di nuovo nei file `.cmd` di compilazione e
  l'SPL linka.

Lezione: con una toolchain non documentata per la piattaforma, compilare senza errori non
basta. Bisogna controllare che i flag attesi vengano davvero passati.

### 4. binman: manca `yamllint`

```
binman: Unknown entry type 'ti-board-config' ... No module named 'yamllint'
```

- **Causa**: binman valida la board config TI con il modulo Python `yamllint`.
- **Soluzione**: `sudo pacman -S yamllint`. Il pacchetto è stato aggiunto alle dipendenze
  della guida.

### 5. U-Boot A53 compilato con clang: la scheda si blocca dopo OP-TEE

Problema emerso solo a runtime, sulla scheda: la build era andata a buon fine.

```
Starting ATF on ARM64 core...
NOTICE:  BL31: v2.15.0(release):6da12e7
I/TC: OP-TEE version: cde9355 (clang version 23.1.4) ...
I/TC: Disabling output console
                                  <- poi più nulla, LED spenti
```

- **Cosa funziona**: l'SPL R5 (clang) carica `tispl.bin` dalla SD, BL31 parte e
  inizializza OP-TEE. `Disabling output console` è normale: OP-TEE spegne la propria
  console.
- **Cosa manca**: la seconda riga `U-Boot SPL 2026.10-...`, cioè l'SPL A53 a cui BL31
  deve saltare (`PRELOADED_BL33_BASE`).
- **Esclusi**:
  - indirizzi incoerenti: BL31 a `0x80000000`, OP-TEE a `0x9e800000` e SPL A53 a
    `0x80080000` coincidono tra TF-A (`plat/ti/k3/platform.mk`), OP-TEE
    (`CFG_TZDRAM_START`) e U-Boot (`CONFIG_K3_*_LOAD_ADDR`, `CONFIG_SPL_TEXT_BASE`);
  - FIT incompleto: `dumpimage -l tispl.bin` mostra ATF, OP-TEE, DM, SPL e dtb;
  - le "outline atomics" citate in `doc/build/clang.rst`: nei binari non ci sono simboli
    `__aarch64_*`.
- **Bisezione**: U-Boot A53 ricompilato con gcc 16.2, con TF-A, OP-TEE e SPL R5 ancora
  compilati con clang. Risultato: compaiono l'SPL A53 e `U-Boot 2026.10-00667-g0a55b098d6f5`
  fino al prompt. Il difetto è quindi nell'SPL A53 compilato con clang.
- **Soluzione adottata**: `build.sh` compila `uboot-a53` con gcc (`TOOLCHAIN_A53=gcc`).
  Con `TOOLCHAIN_A53=llvm` si può riprovare clang.
- **Aperto**: la causa precisa in clang è da indagare, per esempio con `CONFIG_DEBUG_UART`
  nell'SPL A53 o confrontando l'SPL A53 clang con quello gcc. Gli artefatti clang sono
  conservati in `out/boot-clang/` e `u-boot/build-a53-clang/`.

### 6. U-Boot vanilla non avvia il kernel Debian `Image.gz`

```
Retrieving file: /Image.gz
kernel_comp_addr_r or kernel_comp_size is not provided!
Boot failed (err=-14)
Scanning bootdev 'mmc@fa10000.bootdev':      <- ripiega sull'eMMC
```

- **Causa**: la Debian avvia un kernel compresso. `booti` lo decomprime solo se sono
  definite `kernel_comp_addr_r` e `kernel_comp_size` (`cmd/booti.c`,
  `doc/develop/distro.rst`). L'U-Boot BeagleBoard le imposta, l'ambiente vanilla della
  BeaglePlay no.
- **Effetto collaterale**: U-Boot passa alla voce `Linux eMMC` e avvia il kernel di
  fabbrica con il device tree di U-Boot (`Skipping fdtdir`). Quel kernel ripete
  all'infinito `am65-cpsw-nuss ... error retrieving port phy: -517` e non arriva al login.
  La scheda sembra impazzita, ma è solo un kernel con il dtb sbagliato.
- **Soluzione**: un file `uEnv.txt` sulla FAT con `kernel_comp_addr_r=0xa0000000` e
  `kernel_comp_size=0x4000000`. U-Boot vanilla lo importa prima di extlinux (`envboot` in
  `include/env/ti/mmc.env`). `0xa0000000` è subito sopra la zona di OP-TEE
  (`0x9e800000` + 24 MiB). `./build.sh collect` genera il file in `out/boot/`. Il kernel
  vanilla non ne ha bisogno, perché si usa `Image` non compresso.

### 7. Kernel vanilla bloccato su `Waiting for root device /dev/mmcblk1p3...`

Prima prova del kernel vanilla (2026-11-06). U-Boot avvia la voce `vanilla` e il kernel
parte (`Linux version 7.4.0-rc1-gf66469d9905b ... clang version 23.1.4, LLD 23.1.4`), ma
non monta il rootfs:

```
[    1.488958] Warning: unable to open an initial console.
[    1.494400] Waiting for root device /dev/mmcblk1p3...
[   11.742069] omap8250 2800000.serial: probe with driver omap8250 failed with error -110
[   12.039465] platform fa00000.mmc: deferred probe pending: platform: wait for supplier
               /bus@f0000/system-controller@44043000/clock-controller
```

- **Causa**: nel `defconfig` arm64 mainline il protocollo TI SCI e i driver che ne
  dipendono sono moduli: `TI_SCI_PROTOCOL`, `TI_SCI_CLK`, `TI_SCI_PM_DOMAINS`,
  `TI_SCI_INTR_IRQCHIP`, `TI_SCI_INTA_IRQCHIP` e `RESET_TI_SCI` sono tutti `=m`
  (`arch/arm64/configs/defconfig`). Sui SoC K3 clock e power domain dei periferici li
  gestisce il firmware TIFS, tramite TI SCI (`system-controller@44043000`). Senza questi
  driver il controller SD (`fa00000.mmc`), l'UART, le GPIO e l'I2C restano in deferred
  probe. Ne nasce un circolo vizioso: i moduli stanno sul rootfs, e il rootfs sta sulla SD
  che non si attiva. Il driver SD `sdhci-am654` è `=y`, ma da solo non basta.
- **Soluzione**: compilare quei sei driver nel kernel (`=y`). In `build.sh`, dopo
  `defconfig`, si eseguono `scripts/config --enable ...` e `olddefconfig`. Il sorgente
  resta vanilla; cambia solo la configurazione. In alternativa servirebbe un initramfs con
  i moduli, come fanno le distribuzioni.
- **Verifica**: nella prova 2 il controller SD parte subito e il rootfs viene montato
  1,8 s dopo l'avvio del kernel (vedi "Prove del kernel vanilla").

## Stato attuale (2026-11-06)

### Build

Tutti gli artefatti sono compilati e raccolti in `out/boot/` con `./build.sh collect`.

| Artefatto | Dimensione | Toolchain verificata (`.comment` dell'ELF) |
|-----------|-----------:|----------------------------------------|
| `bl31.bin` (TF-A) | 44 608 B | clang 23.1.4 + ld.lld |
| `tee-raw.bin` (OP-TEE) | 519 736 B | clang 23.1.4 + LLD 23.1.4 |
| `tiboot3.bin` (U-Boot SPL R5, `tiboot3-am62x-gp-evm.bin`) | 311 729 B | clang 23.1.4 + ld GNU (`arm-none-eabi-`) |
| `tispl.bin` (BL31 + OP-TEE + DM + SPL A53) | 1 056 807 B | SPL A53: gcc 16.2 (problema 5); BL31 e OP-TEE: clang |
| `u-boot.img` (U-Boot A53) | 1 203 552 B | gcc 16.2 (`aarch64-linux-gnu-`) |
| `Image-vanilla` (Linux `7.4.0-rc1`, commit `f66469d99`, `defconfig` + TI SCI `=y`) | 42 256 896 B | clang 23.1.4 + LLD 23.1.4 |
| `k3-am625-beagleplay-vanilla.dtb` | 63 745 B | dtc (dal sorgente kernel) |

In più `out/boot/uEnv.txt` (342 byte), generato da `collect` (problema 6).

### Prove di U-Boot vanilla sulla scheda (2026-11-06)

Procedura: guida §4, tutto dal PC con la SD estratta. I file originali della SD
(`tiboot3.bin`, `tispl.bin`, `u-boot.img`, `extlinux/`) sono salvati in
`backup/sd-boot-2026.07/`.

| Prova | File sulla FAT | Esito |
|-------|----------------|-------|
| 1 | tutto clang | SPL R5, BL31 e OP-TEE partono, poi silenzio dopo `I/TC: Disabling output console` (problema 5) |
| 2 | U-Boot A53 gcc, resto clang | U-Boot 2026.10 parte, ma il kernel Debian `Image.gz` non viene avviato. U-Boot ripiega sull'eMMC, e il kernel di fabbrica va in loop (problema 6) |
| 3 | come la 2 + `uEnv.txt` | **riuscita**: la Debian della SD arriva al login |

Log della prova 3 (abbreviato):

```
U-Boot SPL 2026.10-00667-g0a55b098d6f5 (Nov 06 2026 - 11:45:52 +0100)   <- SPL R5 (clang)
SYSFW ABI: 4.0 (firmware rev 0x000c '12.2.0--v12.02.00 (Clever Cat)')
Trying to boot from MMC2
Starting ATF on ARM64 core...
NOTICE:  BL31: v2.15.0(release):6da12e7
I/TC: OP-TEE version: cde9355 (clang version 23.1.4) #1 Fri Nov  6 10:31:28 UTC 2026 aarch64
I/TC: Disabling output console
U-Boot SPL 2026.10-00667-g0a55b098d6f5 (Nov 06 2026 - 14:57:02 +0100)   <- SPL A53 (gcc)
Trying to boot from MMC2
U-Boot 2026.10-00667-g0a55b098d6f5 (Nov 06 2026 - 14:57:02 +0100)       <- U-Boot vanilla
SoC:   AM62X SR1.0 GP
Model: BeagleBoard.org BeaglePlay
DRAM:  2 GiB
MMC:   mmc@fa10000: 0, mmc@fa00000: 1, mmc@fa20000: 2
SD/MMC found on device 1
Loaded env from uEnv.txt
Importing environment from mmc1 ...
** Booting bootflow 'mmc@fa00000.bootdev.part_1' with extlinux
Enter choice: 5:	microSD (default)
Retrieving file: /Image.gz
append: console=ttyS2,115200n8 root=/dev/mmcblk1p3 ro rootfstype=ext4 ... quiet
Retrieving file: /ti/k3-am625-beagleplay.dtb
   Uncompressing Kernel Image to 0
Starting kernel ...
Debian GNU/Linux 13 beagleplay ttyS2
beagleplay login: nik
```

Cosa dimostra il log:
- **`U-Boot SPL 2026.10-00667-g0a55b098d6f5`** come prima riga: la ROM ha caricato il
  `tiboot3.bin` vanilla dalla SD (`MMC2` per la ROM, `mmc@fa00000` per U-Boot).
- **`U-Boot 2026.10-00667-g0a55b098d6f5`**: U-Boot proper vanilla, mainline.
  `-00667-g0a55b098d6f5` indica 667 commit dopo il tag v2026.10.
- **`Loaded env from uEnv.txt`**: le variabili per il kernel compresso sono state importate.
- **`mmc@fa00000.bootdev`**: extlinux è stato letto dalla SD, non dall'eMMC (`mmc@fa10000`).
- Gli avvisi del kernel (`bpf-restrict-fs`, `bq32k`, `remoteproc0`) sono gli stessi già
  visti con l'U-Boot BeagleBoard e non dipendono da U-Boot.

### Prove del kernel vanilla sulla scheda (2026-11-06)

Procedura: guida §5, tutto dal PC con la SD estratta. In `extlinux.conf` c'è la voce
`vanilla` con `default vanilla`; la voce Debian resta come riserva.

| Prova | Kernel | Esito |
|-------|--------|-------|
| 1 | `defconfig` puro | il kernel parte, poi resta su `Waiting for root device /dev/mmcblk1p3` (problema 7) |
| 2 | `defconfig` + TI SCI `=y` | **riuscita**: rootfs montato, systemd, login; `uname -r` = `7.4.0-rc1-gf66469d9905b` |

Log della prova 2 (abbreviato; la parte U-Boot è identica alla prova 3 di U-Boot):

```
U-Boot 2026.10-00667-g0a55b098d6f5 (Nov 06 2026 - 14:57:02 +0100)
Loaded env from uEnv.txt
** Booting bootflow 'mmc@fa00000.bootdev.part_1' with extlinux
Enter choice: 6:	vanilla
Retrieving file: /Image-vanilla
append: console=ttyS2,115200n8 earlycon root=/dev/mmcblk1p3 rw rootfstype=ext4 rootwait
Retrieving file: /k3-am625-beagleplay-vanilla.dtb
Starting kernel ...
[    0.000000] Linux version 7.4.0-rc1-gf66469d9905b (nik@workstation) (clang version 23.1.4, LLD 23.1.4) #2 SMP PREEMPT_DYNAMIC Fri Nov  6 16:20:30 CET 2026
[    0.000000] Machine model: BeagleBoard.org BeaglePlay
[    1.805352] mmc1: SDHCI controller on fa00000.mmc [fa00000.mmc] using ADMA 64-bit
[    1.805741] Waiting for root device /dev/mmcblk1p3...
[    2.050557] mmcblk1: mmc1:aaaa SC32G 29.7 GiB
[    2.103185] EXT4-fs (mmcblk1p3): mounted filesystem b4824503-... r/w with ordered data mode.
[    2.165282] Run /sbin/init as init process
Welcome to Debian GNU/Linux 13 (trixie)!
beagleplay login: nik
nik@beagleplay:~$ uname -r
7.4.0-rc1-gf66469d9905b
```

Cosa dimostra il log:
- **`Enter choice: 6:	vanilla`** senza input: U-Boot ha scelto da solo la voce di
  default.
- **`Linux version 7.4.0-rc1-gf66469d9905b ... clang version 23.1.4, LLD 23.1.4`**: kernel
  mainline (commit `f66469d99`), compilato e linkato con LLVM. `#2` è la seconda build,
  quella con TI SCI built-in.
- **`EXT4-fs (mmcblk1p3): mounted`** e **`uname -r`**: il rootfs della SD è montato e il
  sistema in esecuzione usa il kernel vanilla. Requisito della tesi raggiunto: U-Boot e
  Linux vanilla.

Avvisi visti nel log, che non impediscono il login:
- `zram-generator: modprobe "zram" failed` e, dopo circa 90 s,
  `Timed out waiting for device dev-zram0.device`: la Debian si aspetta lo swap compresso
  zram, ma nel `defconfig` `CONFIG_ZRAM` non è impostato. Rallenta il boot di circa 90 s.
  Si può risolvere abilitando `ZRAM` (anche come modulo) o disattivando zram nella Debian.
- `Failed to start iwd.service` e `Failed to start docker.service`: servizi della Debian
  IoT che chiedono funzioni del kernel assenti nel `defconfig`. La causa precisa non è
  stata indagata. Nella config mancano per esempio `CRYPTO_USER_API_SKCIPHER` e
  `KEY_DH_OPERATIONS`, che `iwd` usa. Non servono per la tesi.
- `cfg80211: failed to load regulatory.db`: manca il database delle regolazioni Wi-Fi nel
  rootfs. Il driver Wi-Fi `wlcore` comunque si carica (`firmware booted`).
- `bq32k 0-0068: Oscillator Failure. Check RTC battery.`: l'RTC non ha batteria. L'ora
  viene ripresa da `/var/lib/systemd/timesync/clock` (resta 2026-09-20 senza rete).
- `bpf-restrict-fs: BPF LSM hook not enabled in the kernel`: come con il kernel Debian.

### Base Debian su microSD

La microSD da 32 GB è stata scritta con
`beagleplay-debian-13.7-iot-v6.18-k3-arm64-2026-09-20-10gb.img.xz`. Utente e password sono
stati impostati in `sysconf.txt` sulla partizione FAT, come chiede la pagina ufficiale.

1. **Primo tentativo: è partito dall'eMMC.** Il tasto USR non era premuto, quindi la ROM ha
   caricato l'U-Boot 2021.01 dell'eMMC. Questo ha trovato `extlinux.conf` sulla SD, ma non
   il device tree (`Failed to load '/k3-am625-beagleplay.dtb'`: la nuova immagine lo tiene
   in `/ti/`), ed è ripiegato sull'eMMC.
2. **Secondo tentativo: avvio dalla microSD riuscito.** Con USR premuto prima di dare
   alimentazione, la prima riga è `U-Boot SPL 2026.07-g497fcbd50a6b`, seguita da
   `Trying to boot from MMC2` e dal bootflow extlinux su `mmc@fa00000` (controller SD).
3. **Primo avvio della Debian.** Il servizio `bbbio-set-sysconf` applica `sysconf.txt` e
   riavvia la scheda due volte. Durante il primo avvio allarga la partizione 3 a tutta la
   SD (`growpart`), rigenera le chiavi SSH, crea l'utente, imposta hostname `beagleplay` e
   timezone, poi riavvia. Al secondo avvio esegue `resize2fs` della partizione 3 e riavvia
   di nuovo. Dal terzo avvio la scheda arriva al login. I riavvii continuano a partire
   dalla SD (`Reset reason: RST`). Per via dell'opzione `quiet` la console sembra ferma:
   basta premere Invio per vedere il prompt.

Verifiche fatte sulla scheda dopo il login:

```
$ cat /proc/cmdline
console=ttyS2,115200n8 root=/dev/mmcblk1p3 ro rootfstype=ext4 fsck.repair=yes resume=/dev/mmcblk1p2 rootwait net.ifnames=0 quiet

$ df -h /
/dev/root        27G  4.6G   22G  18% /

$ lsblk
mmcblk0      14.6G  disk            <- eMMC (Debian di fabbrica, non toccata)
|-mmcblk0p1   128M  part
`-mmcblk0p2  14.5G  part
mmcblk0boot0    4M  disk
mmcblk0boot1    4M  disk
mmcblk1      29.7G  disk            <- microSD
|-mmcblk1p1   256M  part /boot/firmware   (FAT, bootloader + kernel + extlinux)
|-mmcblk1p2     2G  part [SWAP]
`-mmcblk1p3  27.5G  part /                (ext4, rootfs)
```

Quindi il rootfs è sulla SD (`mmcblk1p3`) e l'eMMC non è montata.

La partizione FAT si vede in Linux come `/boot/firmware`. È qui che andranno copiati i file
di boot vanilla.

Il numero degli alias (mmc0 = eMMC, mmc1 = SD) coincide con quello del device tree
mainline. Per questo la voce `extlinux` del kernel vanilla può usare
`root=/dev/mmcblk1p3`.

Avvisi innocui visti nel log:
- `bpf-restrict-fs: Failed to load BPF object`: funzione di systemd che questo kernel non
  supporta.
- `bq32k ... unable to read the hardware clock`: l'RTC non è ancora impostato.
- `remoteproc0: request_firmware failed: -2`: manca il firmware di un coprocessore non
  usato.
- `watchdog did not stop!`: messaggio normale durante il riavvio.

### Come riconoscere da dove parte la scheda

Conta la **prima riga dell'SPL** sulla seriale. Il menu extlinux non basta, perché anche
l'U-Boot dell'eMMC scansiona la SD e mostra le voci "microSD".

| Prima riga | Sorgente |
|------------|----------|
| `U-Boot SPL 2021.01-gb248392d (Jan 04 2023 ...)` | eMMC (fabbrica) |
| `U-Boot SPL 2026.07-g497fcbd50a6b (Sep 10 2026 ...)` | microSD, U-Boot BeagleBoard della Debian 13.7 |
| `U-Boot SPL 2026.10-...` con la data della build | microSD, U-Boot vanilla di questo progetto |

## Prossimi passi

1. ~~**U-Boot vanilla.**~~ Fatto il 2026-11-06 (prova 3).
2. ~~**Kernel vanilla.**~~ Fatto il 2026-11-06 (prova 2): `uname -r` =
   `7.4.0-rc1-gf66469d9905b`.
3. Opzionale: abilitare `ZRAM` nel kernel per eliminare l'attesa di 90 s al boot.
4. Opzionale: capire perché U-Boot A53 compilato con clang si blocca (problema 5).
5. Opzionale: rootfs minimale con Buildroot.
6. Fase successiva della tesi: applicazioni bare-metal (vedi README).

## Rischi aperti

- **U-Boot su K3 compilato con clang** non è documentato upstream. È già successo con la
  parte A53 (problema 5), che ora si compila con gcc. Resta aperta la causa del difetto.
  L'SPL R5 compilato con clang funziona sulla scheda.
- **Kernel vanilla con clang**: funziona sulla scheda, con TI SCI built-in (problema 7).
  Non usa `uEnv.txt` (si avvia `Image` non compresso). Il `defconfig` non copre tutto
  quello che si aspetta la Debian IoT (zram, iwd, docker): sono funzioni accessorie, non
  servono per il boot.
- **Moduli del kernel**: il kernel vanilla usa i propri in
  `/lib/modules/7.4.0-rc1-gf66469d9905b`, installati con `./build.sh modules-install`.
  Vanno reinstallati a ogni cambio di configurazione. Quelli del kernel BeagleBoard 6.18
  restano sulla SD per la voce Debian.
- **Ripristino**: se il nuovo U-Boot non parte, basta accendere senza USR per tornare
  all'eMMC. Poi, dal PC, si rimettono sulla SD i file di boot salvati in
  `backup/sd-boot-2026.07/` e si cancella `uEnv.txt` (guida §4.8).
