# alcatraz

macOS locked in a container. One Docker image runs QEMU with KVM, boots [OSX-KVM](https://github.com/kholia/OSX-KVM)'s OpenCore, and installs macOS from Apple's recovery servers.

alcatraz is a hard fork of [Docker-OSX](https://github.com/sickcodes/Docker-OSX). Disks and `docker run` flags from Docker-OSX work unchanged. See [Coming from Docker-OSX](#coming-from-docker-osx).

## What's in the image

The image is Arch Linux with QEMU, OVMF firmware and OSX-KVM's OpenCore bootdisk. It holds no macOS. On first start the container downloads the recovery image for the version you pick from Apple's servers, creates an empty 256 GB disk (a qcow2 file, so it only takes the space macOS writes), and boots the installer.

Read [Is this legal?](FAQ.md#is-this-legal) before you use it.

## Requirements

- A Linux x86_64 host with KVM. `/dev/kvm` must exist, which needs virtualization turned on in the BIOS.
- Docker, with your user in the `docker` group.
- An X11 display for the QEMU window. Xwayland works.
- About 60 GB free under `/var/lib/docker` for a fresh install, more with Xcode.
- 4 GB of RAM for the guest by default, plus what the host needs.

Windows 11 works through WSL2 with nested virtualization. See [Can I run it on Windows?](FAQ.md#run-on-windows).

## Quick start

```bash
docker run -it \
    --device /dev/kvm \
    -p 50922:10022 \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -e "DISPLAY=${DISPLAY:-:0.0}" \
    ghcr.io/shbernal/alcatraz:latest
```

This installs macOS Tahoe. To install another version, add `-e SHORTNAME=<name>`:

| `SHORTNAME` | macOS |
|---|---|
| `high-sierra` | High Sierra (10.13) |
| `mojave` | Mojave (10.14) |
| `catalina` | Catalina (10.15) |
| `big-sur` | Big Sur (11) |
| `monterey` | Monterey (12) |
| `ventura` | Ventura (13) |
| `sonoma` | Sonoma (14) |
| `sequoia` | Sequoia (15) |
| `tahoe` | Tahoe (26), the default |

High Sierra and older also need `-e NETWORKING=vmxnet3`.

### Installing

1. In the OpenCore picker, press Enter on the macOS Base System.
2. Open Disk Utility and erase the largest disk, around 256 GB. Leave the smaller ones alone.
3. Quit Disk Utility, choose Reinstall macOS and install to the disk you just erased.

The installer reboots several times and its time estimates mean nothing. Pick the installed disk in the picker after each reboot. Once macOS is installed, [skip the picker](#skipping-the-picker).

## Keep your disk

The disk lives inside the container. Start the same container again instead of running a new one:

```bash
docker ps --all --filter ancestor=ghcr.io/shbernal/alcatraz:latest
docker start -ai <container-id>
```

`docker rm` deletes the disk with the container. To keep the disk on the host, create it there and mount it:

```bash
docker run --rm --user "$(id -u):$(id -g)" -v "${PWD}:/out" --entrypoint qemu-img \
    ghcr.io/shbernal/alcatraz:latest create -f qcow2 /out/mac_hdd_ng.img 256G

docker run -it \
    --device /dev/kvm \
    -p 50922:10022 \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -e "DISPLAY=${DISPLAY:-:0.0}" \
    -v "${PWD}/mac_hdd_ng.img:/image" \
    -e IMAGE_PATH=/image \
    ghcr.io/shbernal/alcatraz:latest
```

The file has to exist before `docker run`. If it doesn't, Docker creates a directory in its place and QEMU fails. To copy the disk out of an existing container, see [Extract the virtual disk](FAQ.md#extract-the-virtual-disk).

### Skipping the picker

`-e NOPICKER=true` boots straight into the installed disk and leaves the installer out.

## SSH and ports

Turn on Remote Login in macOS (System Settings, General, Sharing). With `-p 50922:10022`, the guest's SSH server answers on the host:

```bash
ssh <macos-user>@localhost -p 50922
```

QEMU forwards container port 10022 (`INTERNAL_SSH_PORT`) to guest port 22, and container port 5900 (`SCREEN_SHARE_PORT`) to guest port 5900 for Screen Sharing. For other ports, add QEMU `hostfwd` rules to `ADDITIONAL_PORTS`, each ending in a comma, and publish the container port:

```bash
    -e ADDITIONAL_PORTS='hostfwd=tcp::10023-:80,hostfwd=tcp::10043-:443,' \
    -p 10023:10023 \
    -p 10043:10043 \
```

With these flags, a web server on guest port 80 answers on host port 10023.

## Configuration

Every setting is an environment variable passed with `-e`.

| Variable | Default | What it does |
|---|---|---|
| `SHORTNAME` | `tahoe` | macOS version to download when `BASESYSTEM_IMAGE` is missing. See [Quick start](#quick-start). |
| `RAM` | `4` | Guest memory in GB. `max` takes all of the host's memory, `half` takes half. |
| `SMP` | `4` | CPU count for QEMU's `-smp`. |
| `CORES` | `4` | Cores for QEMU's `-smp`. |
| `CPU_STRING` | | Replaces the whole `-smp` value, for example `8,sockets=4,cores=2`. |
| `CPU` | `Skylake-Client,-hle,-rtm` | QEMU CPU model. |
| `CPUID_FLAGS` | `kvm=on,vendor=GenuineIntel,+invtsc,…` | CPU flags appended to `CPU`. |
| `BOOT_ARGS` | | Text appended to the `-cpu` value after `CPUID_FLAGS`. |
| `KVM` | `accel=kvm:tcg` | Appended to `-machine q35,`. |
| `IMAGE_PATH` | `/home/arch/OSX-KVM/mac_hdd_ng.img` | The macOS disk. |
| `IMAGE_FORMAT` | `qcow2` | Format of `IMAGE_PATH`. |
| `NOPICKER` | `false` | `true` hides the OpenCore picker and leaves the installer out. |
| `BOOTDISK` | | OpenCore bootdisk. Empty means the stock `OpenCore/OpenCore.qcow2`, or `OpenCore/OpenCore-nopicker.qcow2` with `NOPICKER=true`. |
| `BASESYSTEM_IMAGE` | `BaseSystem.img` | Installer image the container looks for before downloading one. |
| `BASESYSTEM_FORMAT` | `qcow2` | Format of the installer image. |
| `NETWORKING` | `virtio-net-pci` | QEMU network device. `vmxnet3` for High Sierra and older, `e1000-82545em` if the network is slow. |
| `MAC_ADDRESS` | `52:54:00:09:49:17` | Guest MAC address. `GENERATE_UNIQUE` sets it. |
| `INTERNAL_SSH_PORT` | `10022` | Container port forwarded to guest port 22. |
| `SCREEN_SHARE_PORT` | `5900` | Container port forwarded to guest port 5900. |
| `ADDITIONAL_PORTS` | | Extra QEMU `hostfwd` rules, each ending in a comma. |
| `AUDIO_DRIVER` | `alsa` | QEMU `-audiodev` backend. `none` turns audio off. |
| `DISPLAY` | `:0.0` | X11 display for the QEMU window. |
| `EXTRA` | | Extra QEMU arguments, split on spaces. |
| `GENERATE_UNIQUE` | `false` | `true` generates new serial numbers and builds a bootdisk with them. |
| `GENERATE_SPECIFIC` | `false` | `true` builds a bootdisk with the serial numbers you pass. |
| `DEVICE_MODEL` | | Mac model for the serial numbers, for example `iMacPro1,1`. |
| `SERIAL` | | Serial number. |
| `BOARD_SERIAL` | | Board serial number (MLB). |
| `UUID` | | System UUID. |
| `WIDTH` | `1920` | Screen width. Needs `GENERATE_UNIQUE` or `GENERATE_SPECIFIC`. |
| `HEIGHT` | `1080` | Screen height. Needs `GENERATE_UNIQUE` or `GENERATE_SPECIFIC`. |
| `ENV` | `/env` | File `GENERATE_UNIQUE` writes the serial numbers to, and `GENERATE_SPECIFIC` reads them from. |
| `MASTER_PLIST_URL` | | OpenCore `config.plist` template to build the bootdisk from, instead of OSX-KVM's. |

The image also sets `USER`, `LIBGUESTFS_DEBUG` and `LIBGUESTFS_TRACE` for its own use.

USB devices, extra disks and shared folders go through QEMU arguments in `EXTRA`. The [FAQ](FAQ.md#usb-devices) has recipes.

## Serial numbers

The stock bootdisk carries OSX-KVM's serial numbers, the same in every install. iMessage and iCloud need your own.

`-e GENERATE_UNIQUE=true` generates a fresh set and builds a new bootdisk with them, which adds about 30 seconds to the start. To keep the same set across containers, save the `ENV` file:

```bash
touch ./serials.env
docker run -it \
    --device /dev/kvm \
    -p 50922:10022 \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -e "DISPLAY=${DISPLAY:-:0.0}" \
    -e GENERATE_UNIQUE=true \
    -v "${PWD}/serials.env:/env" \
    ghcr.io/shbernal/alcatraz:latest
```

Next time, replace `GENERATE_UNIQUE=true` with `GENERATE_SPECIFIC=true` and keep the `/env` mount. You can also pass the values directly:

```bash
    -e GENERATE_SPECIFIC=true \
    -e DEVICE_MODEL="iMacPro1,1" \
    -e SERIAL="C02TW0WAHX87" \
    -e BOARD_SERIAL="C027251024NJG36UE" \
    -e UUID="5CCB366D-9118-4C61-A00A-E5BAF3BED451" \
    -e MAC_ADDRESS="A8:5C:2C:9A:46:2F" \
```

Check the serial number inside macOS with `ioreg -l | grep IOPlatformSerialNumber` before you sign in to anything.

Both options write the values into OSX-KVM's `config.plist`. `MASTER_PLIST_URL` swaps in another template with `{{DEVICE_MODEL}}`, `{{SERIAL}}`, `{{BOARD_SERIAL}}`, `{{UUID}}`, `{{ROM}}`, `{{WIDTH}}` and `{{HEIGHT}}` placeholders, such as the ones in [osx-serial-generator](https://github.com/sickcodes/osx-serial-generator).

`WIDTH` and `HEIGHT` live in the same `config.plist`, so a resolution change also needs one of the two options.

## Coming from Docker-OSX

Replace `sickcodes/docker-osx:<tag>` with `ghcr.io/shbernal/alcatraz:latest` and keep the rest of the command. Environment variable names and defaults, the `arch` user and the `/home/arch/OSX-KVM` layout are the same, so existing disks boot.

What changed:

- There is one image. For the old `:naked` image, mount the disk and add `-e IMAGE_PATH=/image`, plus `-e NOPICKER=true` if you relied on its default.
- The `:auto`, `:naked-auto` and VNC images are gone, and so are their pre-installed disks.
- `Launch-nopicker.sh` is gone. Use `-e NOPICKER=true`.
- The `/home/arch/OSX-KVM/OpenCore-Catalina` symlink is gone. The directory is `OpenCore`.

Disks installed with Docker-OSX's older defaults, a `Penryn` CPU and a `vmxnet3` network card, boot on the current ones. To keep the old virtual hardware for such a disk anyway:

```bash
    -e CPU=Penryn \
    -e CPUID_FLAGS='vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on,+ssse3,+sse4.2,+popcnt,+avx,+aes,+xsave,+xsaveopt,check,' \
    -e NETWORKING=vmxnet3 \
```

## Building

```bash
docker build -t alcatraz .
```

The build pins OSX-KVM to a commit with `ARG OSX_KVM_REF` in the [Dockerfile](Dockerfile). OSX-KVM supplies the firmware, the OpenCore bootdisk and its config, and the recovery download script, so a bump can break booting. After changing the commit, build, then boot an existing disk and a fresh install.

`archlinux:base-devel` is not pinned. Pass its digest as `--build-arg BASE_DIGEST=sha256:…` to record it in the image's `org.opencontainers.image.base.digest` label.

The scripts the container runs are in [rootfs/home/arch/OSX-KVM](rootfs/home/arch/OSX-KVM), at the path they take in the image. `serial/` holds the serial number scripts from [osx-serial-generator](https://github.com/sickcodes/osx-serial-generator) at 908b3d6.

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
