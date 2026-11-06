# Bare Metal ARM Development

Bare-metal experiments on the **BeaglePlay** (TI AM625, Cortex-A53).
The project collects the components built along the way: UART bring-up,
a U-Boot + Linux build, C utilities, and a small bare-metal shell/calculator.

> Work in progress. Started as part of a thesis on ARM OS prototyping.

## Roadmap

### 1. UART bring-up
- [x] Wire the FTDI 3.3 V cable (GND / RX / TX, no VCC)
- [x] Open serial console at 115200 8N1
- [x] Boot the official Debian image from SD and see output on UART

### 2. U-Boot + Linux
- [x] Build toolchains (`arm-none-eabi-`, `aarch64-linux-gnu-`)
- [x] Build TF-A and fetch ti-linux-firmware
- [x] Build U-Boot R5 (`tiboot3.bin`)
- [x] Build U-Boot A53 (`tispl.bin`, `u-boot.img`)
- [x] Boot custom U-Boot from SD
- [x] Build Linux kernel (`Image` + `k3-am625-beagleplay.dtb`)
- [x] Boot mainline Linux from SD with vanilla U-Boot (Debian rootfs, `uname -r` = `7.4.0-rc1-gf66469d9905b`)
- [ ] Build root filesystem (Buildroot)
- [ ] Full custom boot to Linux shell

### 3. Working C code
- [ ] Host-side utilities (strings, parsing) tested with `gcc`
- [ ] Cross-compile with `aarch64-linux-gnu-gcc`
- [ ] Run a C program on the board under Linux

### 4. Bare-metal application
- [ ] `start.S` (stack, `.bss`, jump to `main`) + linker script
- [ ] Load via U-Boot (`loady` + `go`)
- [ ] UART driver (polling): `uart_putc`, `uart_getc`, `uart_puts`
- [ ] "Hello world" over UART
- [ ] Line input with echo and backspace
- [ ] Freestanding libc bits: `memcpy`, `memset`, `strcmp`, `atoi`/`strtol`
- [ ] Minimal `printf`
- [ ] Expression parser (operator precedence)
- [ ] Shell/calculator REPL

### Next steps (optional)
- [ ] Exception vector table + `ESR_EL2` dump
- [ ] GIC (GICv3) setup
- [ ] Interrupt-driven UART with ring buffer

## Repository layout

```
uart/    UART driver
lib/     freestanding C utilities
shell/   REPL and calculator
docs/    notes, wiring, build instructions
```

## Hardware

- BeaglePlay
- FTDI USB-UART cable (3.3 V)
- microSD card
