## Fase 1) collegamento UART e test output su schermo

fonte:
https://docs.beagleboard.org/boards/beagleplay/demos-and-tutorials/using-serial-console.html#beagleplay-serial-console

note:
software tio non disponibile nella mia distribuzione, ho usato picocom:
```picocom -b 115200 /dev/ttyUSB0```

output (USB-LED 0 lampeggiante di verde alla fine):

```U-Boot SPL 2021.01-gb248392d (Jan 04 2023 - 19:38:45 +0000)
SYSFW ABI: 3.1 (firmware rev 0x0008 '8.5.3--v08.05.03 (Chill Capybar')
SPL initial stack usage: 13424 bytes
Trying to boot from MMC1
Loading Environment from MMC... MMC: block number 0x3500 exceeds max(0x2000)
*** Warning - !read failed, using default environment

init_env from device 9 not supported!
Starting ATF on ARM64 core...

NOTICE:  BL31: v2.7(release):v2.7.0-519-gc19116dd6
NOTICE:  BL31: Built : 19:38:45, Jan  4 2023
I/TC:
I/TC: OP-TEE version: 3.19.0-rc1 (gcc version 10.2.1 20210110 (Debian 10.2.1-6)) #1 Wed Jan  4 19:38:45 UTC 2023 aarch64
I/TC: WARNING: This OP-TEE configuration might be insecure!
I/TC: WARNING: Please check https://optee.readthedocs.io/en/latest/architecture/porting_guidelines.html
I/TC: Primary CPU initializing
I/TC: SYSFW ABI: 3.1 (firmware rev 0x0008 '8.5.3--v08.05.03 (Chill Capybar')
I/TC: HUK Initialized
I/TC: Primary CPU switching to normal world boot

U-Boot SPL 2021.01-gb248392d (Jan 04 2023 - 19:38:45 +0000)
SYSFW ABI: 3.1 (firmware rev 0x0008 '8.5.3--v08.05.03 (Chill Capybar')
Trying to boot from MMC1


U-Boot 2021.01-gb248392d (Jan 04 2023 - 19:38:45 +0000)

SoC:   AM62X SR1.0 GP
Model: BeagleBoard.org BeaglePlay
Board: BEAGLEPLAY-A0- rev 02
DRAM:  2 GiB
MMC:   mmc@fa10000: 0, mmc@fa00000: 1, mmc@fa20000: 2
Loading Environment from MMC... MMC: block number 0x3500 exceeds max(0x2000)
*** Warning - !read failed, using default environment

In:    serial@2800000
Out:   serial@2800000
Err:   serial@2800000
Error: Can't set serial# to SSSS
Net:   Could not get PHY for ethernet@8000000port@1: addr 0
am65_cpsw_nuss_port ethernet@8000000port@1: phy_connect() failed
No ethernet found.

Press SPACE to abort autoboot in 2 seconds
MMC: no card present
switch to partitions #0, OK
mmc0(part 0) is current device
Scanning mmc 0:1...
Found /extlinux/extlinux.conf
Retrieving file: /extlinux/extlinux.conf
189 bytes read in 7 ms (26.4 KiB/s)
1:	Linux eMMC
Retrieving file: /initrd.img
15402499 bytes read in 3193 ms (4.6 MiB/s)
Retrieving file: /Image
29315584 bytes read in 4296 ms (6.5 MiB/s)
append: root=/dev/mmcblk0p2 ro rootfstype=ext4 rootwait net.ifnames=0 quiet
Retrieving file: /k3-am625-beagleplay.dtb
61704 bytes read in 37 ms (1.6 MiB/s)
## Flattened Device Tree blob at 88000000
   Booting using the fdt blob at 0x88000000
   Loading Ramdisk to 8f14f000, end 8ffff603 ... OK
   Loading Device Tree to 000000008f13c000, end 000000008f14e107 ... OK

Starting kernel ...

I/TC: Secondary CPU 1 initializing
I/TC: Secondary CPU 1 switching to normal world boot
I/TC: Secondary CPU 2 initializing
I/TC: Secondary CPU 2 switching to normal world boot
I/TC: Secondary CPU 3 initializing
I/TC: Secondary CPU 3 switching to normal world boot
[    1.962102] am65-cpsw-nuss 8000000.ethernet: Use random MAC address
[    2.078730] sdhci-am654 fa00000.mmc: parsing dt failed (-517)
[    2.091939] bq32k 0-0068: hctosys: unable to read the hardware clock
[    2.446537] debugfs: Directory 'pd:53' with parent 'pm_genpd' already present!
[    2.453879] debugfs: Directory 'pd:52' with parent 'pm_genpd' already present!
[    2.461226] debugfs: Directory 'pd:51' with parent 'pm_genpd' already present!
[    2.468910] debugfs: Directory 'pd:182' with parent 'pm_genpd' already present!
[    3.867897] hub 2-0:1.0: config failed, hub doesn't have any ports! (err -19)
[   13.624560] davinci-mcasp 2b10000.mcasp: IRQ common not found
[   13.771255] platform 78000000.r5f: configured R5F for IPC-only mode
[   13.777686] platform 78000000.r5f: device does not have reserved memory regions, ret = -22
[   13.786092] k3_r5_rproc bus@f0000:bus@b00000:r5fss@78000000: reserved memory init failed, ret = -22
[   13.795336] k3_r5_rproc bus@f0000:bus@b00000:r5fss@78000000: k3_r5_cluster_rproc_init failed, ret = -22
[  OK  ] Finished Tell Plymouth To Write Out Runtime Data.
[  OK  ] Finished Set console font and keymap.
[  OK  ] Finished Create Volatile Files and Directories.
         Starting Network Name Resolution...
         Starting Network Time Synchronization...
         Starting Update UTMP about System Boot/Shutdown...
[  OK  ] Finished Update UTMP about System Boot/Shutdown.
[  OK  ] Started Network Time Synchronization.
[  OK  ] Reached target System Time Set.
[  OK  ] Reached target System Time Synchronized.
[  OK  ] Finished Load AppArmor profiles.
[  OK  ] Reached target System Initialization.
[  OK  ] Started Periodic ext4 Onli…ata Check for All Filesystems.
[  OK  ] Started Discard unused blocks once a week.
[  OK  ] Started Daily rotation of log files.
[  OK  ] Started Daily Cleanup of Temporary Directories.
[  OK  ] Reached target Timers.
[  OK  ] Listening on Avahi mDNS/DNS-SD Stack Activation Socket.
[  OK  ] Listening on D-Bus System Message Bus Socket.
         Starting Docker Socket for the API.
[  OK  ] Listening on GPS (Global P…ioning System) Daemon Sockets.
         Starting Raise network interfaces...
[  OK  ] Listening on Docker Socket for the API.
[  OK  ] Reached target Sockets.
[  OK  ] Reached target Basic System.
         Starting Save/Restore Sound Card State...
         Starting Avahi mDNS/DNS-SD Stack...
         Starting BeagleBoard Generate Symlinks...
         Starting BeagleBoard.org USB gadgets...
[  OK  ] Started Regular background program processing daemon.
[  OK  ] Started D-Bus System Message Bus.
         Starting dphys-swapfile - …unt, and delete a swap file...
         Starting Remove Stale Onli…t4 Metadata Check Snapshots...
         Starting Initialize hardware monitoring sensors...
         Starting System Logging Service...
         Starting User Login Management...
         Starting Load/Save RF Kill Switch Status...
         Starting LSB: Start daemon at boot time...
         Starting Disk Manager...
         Starting WPA supplicant...
[  OK  ] Finished Save/Restore Sound Card State.
[  OK  ] Started Load/Save RF Kill Switch Status.
[  OK  ] Created slice system-wpa_supplicant.slice.
[  OK  ] Reached target Sound Card.
[  OK  ] Started WPA supplicant dae… (interface-specific version).
[  OK  ] Finished Initialize hardware monitoring sensors.
[  OK  ] Finished BeagleBoard Generate Symlinks.
[  OK  ] Finished Remove Stale Onli…ext4 Metadata Check Snapshots.
[  OK  ] Found device /dev/ttyGS0.
[  OK  ] Started System Logging Service.
[  OK  ] Finished Raise network interfaces.
[  OK  ] Started Network Name Resolution.
[  OK  ] Reached target Host and Network Name Lookups.
[  OK  ] Started LSB: Start daemon at boot time.
[  OK  ] Finished dphys-swapfile - …mount, and delete a swap file.
[  OK  ] Started User Login Management.
[  OK  ] Started Avahi mDNS/DNS-SD Stack.
[  OK  ] Started WPA supplicant.
[  OK  ] Reached target Network.
[  OK  ] Reached target Network is Online.
         Starting BeagleBoard.org Code Server...
         Starting containerd container runtime...
         Starting LSB: disk temperature monitoring daemon...
         Starting Access point and …rver for Wi-Fi and Ethernet...
         Starting Create 6lowpan (IEEE802.15.4) network device...
         Starting A high performanc… and a reverse proxy server...
         Starting OpenBSD Secure Shell server...
         Starting Permit User Sessions...
[  OK  ] Started LSB: disk temperature monitoring daemon.
[  OK  ] Finished Permit User Sessions.
         Starting Light Display Manager...
         Starting Hold until boot process finishes up...
[  OK  ] Finished Create 6lowpan (IEEE802.15.4) network device.
[  OK  ] Started Access point and a…server for Wi-Fi and Ethernet.
[  OK  ] Started OpenBSD Secure Shell server.
         Starting Authorization Manager...
[  OK  ] Started BeagleBoard.org Code Server.
[FAILED] Failed to start Light Display Manager.

Debian GNU/Linux 11 BeaglePlay ttyS2

BeagleBoard.org Debian Bullseye Xfce Image 2023-02-04
Support: https://bbb.io/debian
default username:password is [debian:temppwd]

BeaglePlay login:
```

Errori su ethernet (credo irrilevanti nel mio caso)

Tentativo di collegamento con nome utente e password di default
```
The programs included with the Debian GNU/Linux system are free software;
the exact distribution terms for each program are described in the
individual files in /usr/share/doc/*/copyright.

Debian GNU/Linux comes with ABSOLUTELY NO WARRANTY, to the extent
permitted by applicable law.
Last login: Sat Feb  4 08:28:52 UTC 2023 from 192.168.7.1 on pts/0
debian@BeaglePlay:~$ [  300.249371] it66121 2-004c: connector is NOT valid yet
[  300.254551] hdmi-audio-codec hdmi-audio-codec.3.auto: ASoC: error at snd_soc_dai_startup on i2s-hifi: -22
[  300.298085] it66121 2-004c: connector is NOT valid yet
[  300.303343] hdmi-audio-codec hdmi-audio-codec.3.auto: ASoC: error at snd_soc_dai_startup on i2s-hifi: -22
[  300.346784] it66121 2-004c: connector is NOT valid yet
[  300.352041] hdmi-audio-codec hdmi-audio-codec.3.auto: ASoC: error at snd_soc_dai_startup on i2s-hifi: -22
```

Tentativo andato a buon fine

Errori su codec audio HDMI (credo irrilevanti nel mio caso)

Spegnimento Board:
```
debian@BeaglePlay:~$ shutdown now
Failed to set wall message, ignoring: Interactive authentication required.
Failed to power off system via logind: Interactive authentication required.
Failed to open initctl fifo: Permission denied
Failed to talk to init daemon.
debian@BeaglePlay:~$ sudo !!
sudo shutdown now
[sudo] password for debian:
[  OK  ] Started Show Plymouth Power Off Screen.
[  OK  ] Stopped User Login Management.
[  OK  ] Stopped User Manager for UID 1000.
         Stopping User Runtime Directory /run/user/1000...
[  OK  ] Unmounted /run/user/1000.
[  OK  ] Stopped User Runtime Directory /run/user/1000.
[  OK  ] Removed slice User Slice of UID 1000.
         Stopping Permit User Sessions...
[  OK  ] Stopped Permit User Sessions.
[  OK  ] Stopped target Network.
[  OK  ] Stopped target Remote File Systems.
         Stopping Raise network interfaces...
         Stopping Network Name Resolution...
         Stopping WPA supplicant...
         Stopping WPA supplicant da…interface-specific version)...
[  OK  ] Stopped WPA supplicant.
         Stopping D-Bus System Message Bus...
[  OK  ] Stopped Network Name Resolution.
         Stopping Network Service...
[  OK  ] Stopped D-Bus System Message Bus.
[  OK  ] Stopped WPA supplicant dae… (interface-specific version).
[  OK  ] Removed slice system-wpa_supplicant.slice.
[  OK  ] Stopped target Basic System.
[  OK  ] Stopped Forward Password R…s to Plymouth Directory Watch.
[  OK  ] Stopped target Paths.
[  OK  ] Stopped target Slices.
[  OK  ] Removed slice User and Session Slice.
[  OK  ] Stopped target Sockets.
[  OK  ] Closed Avahi mDNS/DNS-SD Stack Activation Socket.
[  OK  ] Closed D-Bus System Message Bus Socket.
[  OK  ] Closed Docker Socket for the API.
[  OK  ] Closed GPS (Global Positioning System) Daemon Sockets.
[  OK  ] Stopped target System Initialization.
[  OK  ] Stopped target Local Encrypted Volumes.
[  OK  ] Stopped Forward Password R…uests to Wall Directory Watch.
[  OK  ] Stopped target Swap.
[  OK  ] Closed Syslog Socket.
         Stopping Network Time Synchronization...
         Stopping Update UTMP about System Boot/Shutdown...
[  OK  ] Stopped Network Time Synchronization.
[  OK  ] Stopped Raise network interfaces.
[  OK  ] Stopped Network Service.
[  OK  ] Stopped Update UTMP about System Boot/Shutdown.
[  OK  ] Stopped Apply Kernel Variables.
[  OK  ] Stopped Load Kernel Modules.
[  OK  ] Stopped Create Volatile Files and Directories.
[  OK  ] Stopped target Local File Systems.
         Unmounting /boot/firmware...
[  OK  ] Unmounted /boot/firmware.
[  OK  ] Stopped target Local File Systems (Pre).
[  OK  ] Reached target Unmount All Filesystems.
[  OK  ] Stopped Create Static Device Nodes in /dev.
[  OK  ] Stopped Create System Users.
[  OK  ] Stopped Remount Root and Kernel File Systems.
[  OK  ] Stopped File System Check on Root Device.
[  OK  ] Reached target Shutdown.
[  OK  ] Reached target Final Step.
[  OK  ] Finished Power-Off.
[  OK  ] Reached target Power-Off.
[  513.978767] reboot: Power down

FATAL: read zero bytes from port
term_exitfunc: reset failed for dev UNKNOWN: Input/output error
```

<hr><br><br>

# Fase 2) Compilazione U-Boot e Linux

fonte: 
