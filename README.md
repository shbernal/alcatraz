# alcatraz

macOS locked in a container. One Docker image runs QEMU with KVM, boots [OSX-KVM](https://github.com/kholia/OSX-KVM)'s OpenCore, and installs macOS from Apple's recovery servers.

alcatraz is a hard fork of [Docker-OSX](https://github.com/sickcodes/Docker-OSX). Disks from Docker-OSX and alcatraz 1.x boot after a rename; see [Upgrading from 1.x or Docker-OSX](#upgrading-from-1x-or-docker-osx).

## What's in the image

The image is Arch Linux with QEMU, OVMF firmware and OSX-KVM's OpenCore bootdisk. It holds no macOS. On first start the container downloads the recovery image for the version you pick from Apple's servers, creates an empty 256 GB disk (a qcow2 file, so it only takes the space macOS writes), and boots the installer. Everything it writes goes to `/data`.

Read [Is this legal?](FAQ.md#is-this-legal) before you use it.

## Requirements

- A Linux x86_64 host with KVM. `/dev/kvm` must exist, which needs virtualization turned on in the BIOS. Tested on Intel. On AMD, CI boots as far as the OpenCore picker; installing macOS there is untested.
- Docker, with your user in the `docker` group.
- An X11 display for the QEMU window. Xwayland works.
- About 60 GB free under `/var/lib/docker` for a fresh install, more with Xcode.
- 4 GB of RAM for the guest by default, plus what the host needs.

Users report that Windows 11 works through WSL2 with nested virtualization; it is untested here. See [Can I run it on Windows?](FAQ.md#run-on-windows).

## Quick start

```bash
docker run -it \
    --device /dev/kvm \
    -p 50922:10022 \
    -v ./mac:/data \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -e "DISPLAY=${DISPLAY:-:0.0}" \
    ghcr.io/shbernal/alcatraz:latest
```

This installs macOS Tahoe, with the disk in `./mac`. To install another version, add `-e MACOS_VERSION=<name>`:

| `MACOS_VERSION` | macOS | Tested |
|---|---|---|
| `high-sierra` | High Sierra (10.13) | |
| `mojave` | Mojave (10.14) | |
| `catalina` | Catalina (10.15) | |
| `big-sur` | Big Sur (11) | |
| `monterey` | Monterey (12) | |
| `ventura` | Ventura (13) | |
| `sonoma` | Sonoma (14) | |
| `sequoia` | Sequoia (15) | yes |
| `tahoe` | Tahoe (26), the default | yes |

Tested versions were installed from scratch and booted with the current OSX-KVM commit. The others are best effort: they worked with Docker-OSX but haven't been installed with the current commit. Tahoe is the last macOS for Intel Macs, so no newer version will run.

High Sierra and older also need `-e NETWORKING=vmxnet3`.

### Installing

1. In the OpenCore picker, press Enter on the macOS Base System.
2. Open Disk Utility and erase the largest disk, around 256 GB. Leave the smaller ones alone.
3. Quit Disk Utility, choose Reinstall macOS and install to the disk you just erased.

The installer reboots several times and its time estimates mean nothing. Pick the installed disk in the picker after each reboot. Once macOS is installed, [skip the picker](#skipping-the-picker).

## Keep your disk

The container keeps everything it writes in `/data`. Mount a host directory there, as in the quick start, and any new container picks up where the last one stopped:

| File | What it is |
|---|---|
| `disk.img` | The macOS disk, created on first start. |
| `installer.img` | The recovery image, downloaded on first start. Delete it to download another `MACOS_VERSION`. |
| `ovmf-vars.fd` | UEFI variables, such as boot order. |
| `serials.env` | Your serial numbers, see [Serial numbers](#serial-numbers). |
| `config.plist` | Optional. An OpenCore config to boot with instead of OSX-KVM's. |
| `bootdisk.qcow2` | The bootdisk built from your serial numbers, `config.plist`, `APPLEID_PATCH` or resolution, rebuilt at every start. |

The container starts as root, gives `/data`, `DISK_PATH` and `INSTALLER_PATH` to its `alcatraz` user (uid 1000), and runs QEMU as that user. A host directory owned by another user works, and ends up owned by uid 1000.

Without the mount, `/data` is an anonymous Docker volume that `docker rm -v` deletes. To copy it out of such a container, see [Extract the virtual disk](FAQ.md#extract-the-virtual-disk).

### Skipping the picker

`-e BOOT_PICKER=false` boots straight into the installed disk and leaves the installer out. Once you use it, you can delete `installer.img`.

## SSH and ports

Turn on Remote Login in macOS (System Settings, General, Sharing). With `-p 50922:10022`, the guest's SSH server answers on the host:

```bash
ssh <macos-user>@localhost -p 50922
```

QEMU forwards container port 10022 (`INTERNAL_SSH_PORT`) to guest port 22, and container port 5900 (`SCREEN_SHARE_PORT`) to guest port 5900 for Screen Sharing. For other ports, list them in `PORTS`, as `PORT` or `CONTAINER:GUEST` with an optional `/udp`, and publish the container port:

```bash
    -e PORTS=10023:80,10043:443 \
    -p 10023:10023 \
    -p 10043:10043 \
```

With these flags, a web server on guest port 80 answers on host port 10023.

## Configuration

Every setting is an environment variable passed with `-e`.

| Variable | Default | What it does |
|---|---|---|
| `MACOS_VERSION` | `tahoe` | macOS version to download when `INSTALLER_PATH` is missing. See [Quick start](#quick-start). |
| `RAM` | `4` | Guest memory in GB. `max` takes all of the host's memory, `half` takes half. |
| `CPUS` | `4` | Number of virtual CPUs. |
| `CORES` | `4` | Cores per socket. `CPUS` divided by `CORES` gives the sockets. |
| `CPU_MODEL` | `Skylake-Client,-hle,-rtm` | QEMU CPU model. |
| `CPU_FLAGS` | `kvm=on,vendor=GenuineIntel,+invtsc,…` | CPU flags appended to `CPU_MODEL`. |
| `ACCEL` | `kvm:tcg` | QEMU accelerators, in order of preference. |
| `DISK_PATH` | `/data/disk.img` | The macOS disk. Created if missing. |
| `DISK_FORMAT` | `qcow2` | Format of `DISK_PATH`. |
| `DISK_SIZE` | `256G` | Size of a newly created disk. |
| `INSTALLER_PATH` | `/data/installer.img` | The recovery image. Downloaded if missing. |
| `INSTALLER_FORMAT` | `qcow2` | Format of `INSTALLER_PATH`. |
| `BOOT_PICKER` | `true` | `false` hides the OpenCore picker and leaves the installer out. |
| `BOOTDISK` | | An OpenCore bootdisk to use as is. Empty means the container picks or builds one. |
| `SERIALS` | `default` | `random` generates serial numbers into `/data/serials.env` if it doesn't exist. See [Serial numbers](#serial-numbers). |
| `DEVICE_MODEL` | | Mac model for the serial numbers, for example `iMacPro1,1`. |
| `SERIAL` | | Serial number. Setting it builds a bootdisk with the values below. |
| `BOARD_SERIAL` | | Board serial number (MLB). |
| `UUID` | | System UUID. |
| `MAC_ADDRESS` | `52:54:00:09:49:17` | Guest MAC address, also the ROM with serial numbers. |
| `APPLEID_PATCH` | `false` | `true` hides the VM from Apple ID, iMessage and iCloud with a kernel patch. See [Apple ID login](FAQ.md#apple-id-login). |
| `WIDTH` | `1920` | Screen width. |
| `HEIGHT` | `1080` | Screen height. A size OVMF doesn't offer, such as `1234x567`, falls back to 1280x800. |
| `NETWORKING` | `virtio-net-pci` | QEMU network device. `vmxnet3` for High Sierra and older, `e1000-82545em` if the network is slow. |
| `INTERNAL_SSH_PORT` | `10022` | Container port forwarded to guest port 22. |
| `SCREEN_SHARE_PORT` | `5900` | Container port forwarded to guest port 5900. |
| `PORTS` | | More forwarded ports, comma-separated: `PORT` or `CONTAINER:GUEST`, with an optional `/udp`. |
| `AUDIO_DRIVER` | `alsa` | QEMU `-audiodev` backend. `none` turns audio off. |
| `DISPLAY` | `:0.0` | X11 display for the QEMU window. |
| `QEMU_ARGS` | | Extra QEMU arguments, split on spaces. |
| `SSH` | `false` | `true` starts an SSH server in the container itself, separate from the guest's. |

USB devices, extra disks and shared folders go through QEMU arguments in `QEMU_ARGS`. The [FAQ](FAQ.md#usb-devices) has recipes.

## Serial numbers

The stock bootdisk carries OSX-KVM's serial numbers, the same in every install. iMessage and iCloud need your own.

`-e SERIALS=random` generates a set into `/data/serials.env` on first start. From then on, every start builds a bootdisk from that file, whether `SERIALS=random` is still set or not. To use serial numbers you already have, write them to `serials.env` yourself or pass them directly, which takes precedence over the file:

```bash
    -e DEVICE_MODEL="iMacPro1,1" \
    -e SERIAL="C02TW0WAHX87" \
    -e BOARD_SERIAL="C027251024NJG36UE" \
    -e UUID="5CCB366D-9118-4C61-A00A-E5BAF3BED451" \
    -e MAC_ADDRESS="A8:5C:2C:9A:46:2F" \
```

Check the serial number inside macOS with `ioreg -l | grep IOPlatformSerialNumber` before you sign in to anything.

The values go into OSX-KVM's `config.plist`, or into `/data/config.plist` if you put one there.

## Upgrading from 1.x or Docker-OSX

2.0 moved everything a container writes to `/data` and renamed most settings. To boot an existing disk, put it in a directory as `disk.img` and mount that directory:

```bash
mkdir mac && mv mac_hdd_ng.img mac/disk.img
docker run ... -v ./mac:/data ghcr.io/shbernal/alcatraz:latest
```

For a disk still inside an old container, `docker cp <container-id>:/home/arch/OSX-KVM/mac_hdd_ng.img mac/disk.img`. With `BOOT_PICKER=true`, the installer is downloaded again on first start.

| 1.x and Docker-OSX | 2.0 |
|---|---|
| `SHORTNAME` | `MACOS_VERSION` |
| `IMAGE_PATH`, `IMAGE_FORMAT` | `DISK_PATH`, `DISK_FORMAT` (default `/data/disk.img`) |
| `BASESYSTEM_IMAGE`, `BASESYSTEM_FORMAT` | `INSTALLER_PATH`, `INSTALLER_FORMAT` |
| `NOPICKER=true` | `BOOT_PICKER=false` |
| `SMP` | `CPUS` |
| `CPU_STRING` | `CPUS` and `CORES` |
| `CPU` | `CPU_MODEL` |
| `CPUID_FLAGS`, `BOOT_ARGS` | `CPU_FLAGS` |
| `KVM=accel=kvm:tcg` | `ACCEL=kvm:tcg` |
| `EXTRA` | `QEMU_ARGS` |
| `ADDITIONAL_PORTS=hostfwd=tcp::23-:23,` | `PORTS=23` |
| `GENERATE_UNIQUE=true` | `SERIALS=random` |
| `GENERATE_SPECIFIC=true` with `ENV=/env` | `/data/serials.env` |
| `GENERATE_SPECIFIC=true` with `SERIAL=…` | `SERIAL=…` |
| `MASTER_PLIST_URL` | `/data/config.plist`, without `{{…}}` placeholders |
| `/home/arch/OSX-KVM` | `/opt/osx-kvm` (upstream) and `/opt/alcatraz` (scripts) |
| `Launch.sh`, `enable-ssh.sh` | `/opt/alcatraz/launch.sh`, `/opt/alcatraz/sshd.sh` |
| user `arch` | user `alcatraz` |

The container's own SSH server no longer starts by default; add `-e SSH=true`. From Docker-OSX, the `:naked`, `:auto` and VNC images are gone; mount your disk and add `-e BOOT_PICKER=false` if you relied on `:naked`'s default.

Disks installed with Docker-OSX's older defaults, a `Penryn` CPU and a `vmxnet3` network card, boot on the current ones. To keep the old virtual hardware for such a disk anyway:

```bash
    -e CPU_MODEL=Penryn \
    -e CPU_FLAGS='vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on,+ssse3,+sse4.2,+popcnt,+avx,+aes,+xsave,+xsaveopt,check' \
    -e NETWORKING=vmxnet3 \
```

## Building

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Troubleshooting

- `error gathering device information while adding custom device "/dev/kvm"` means the host has no KVM. See [KVM error](FAQ.md#kvm-error).
- `gtk initialization failed`, or no window, means the container can't reach your X server. See [GTK initialization failed](FAQ.md#gtk-initialization-failed).
- `permission denied` or `unknown server OS` from `docker`: see [Docker errors](FAQ.md#docker-errors).
- The installer offers no disk to install on until you erase it in Disk Utility. See [No disk to install on](FAQ.md#no-disk-to-install-on).
- `cannot set up guest memory 'pc.ram'` means `RAM` is larger than the free memory. See [RAM and CPUs](FAQ.md#ram-and-cpus).

Pages of `ALSA lib` errors at start are harmless. See [ALSA error](FAQ.md#alsa-error).

## Credits and license

alcatraz is a hard fork of [Docker-OSX](https://github.com/sickcodes/Docker-OSX) by [Sick.Codes](https://sick.codes), modified since September 2026. It builds on [OSX-KVM](https://github.com/kholia/OSX-KVM), [KVM-OpenCore](https://github.com/thenickdude/KVM-Opencore) and [OpenCore](https://github.com/acidanthera/OpenCorePkg). [CREDITS.md](CREDITS.md) lists them along with Docker-OSX's contributors.

Copyright (C) 2020-2025 Sick.Codes and Docker-OSX contributors<br>
Copyright (C) 2026 shbernal

Licensed under the GNU General Public License v3.0 or later. See [LICENSE](LICENSE).
