# Configuration

Every setting is an environment variable passed with `-e`.

## Settings

| Variable | Default | What it does |
|---|---|---|
| `MACOS_VERSION` | `tahoe` | macOS version to download when `INSTALLER_PATH` is missing. See [the version table](../README.md#pick-a-macos-version). |
| `RAM` | `4` | Guest memory in GB. `max` takes all of the host's memory, `half` takes half. |
| `CPUS` | `4` | Number of virtual CPUs. |
| `CORES` | `4` | Cores per socket. `CPUS` divided by `CORES` gives the sockets. |
| `CPU_MODEL` | `Skylake-Client,-hle,-rtm` | QEMU CPU model. |
| `CPU_FLAGS` | `kvm=on,vendor=GenuineIntel,+invtsc,…` | CPU flags appended to `CPU_MODEL`. |
| `ACCEL` | `kvm:tcg` | QEMU accelerators, in order of preference. |
| `DISK_PATH` | `/data/disk.qcow2` | The macOS disk. Created if missing. |
| `DISK_FORMAT` | `qcow2` | Format of `DISK_PATH`. |
| `DISK_SIZE` | `256G` | Size of a newly created disk. |
| `INSTALLER_PATH` | `/data/installer.img` | The recovery image. Downloaded if missing. |
| `INSTALLER_FORMAT` | `qcow2` | Format of `INSTALLER_PATH`. |
| `INSTALLER` | `true` | `false` neither downloads nor attaches the installer. See [After installing](../README.md#after-installing). |
| `BOOT_PICKER` | `true` | `false` hides the OpenCore picker and boots the macOS disk. |
| `BOOTDISK` | | An OpenCore bootdisk to use as is. Empty means the container picks or builds one. |
| `SERIALS` | `default` | `random` generates serial numbers into `/data/serials.env` if it doesn't exist. See [Serial numbers](#serial-numbers). |
| `DEVICE_MODEL` | | Mac model for the serial numbers, for example `iMacPro1,1`. |
| `SERIAL` | | Serial number. Setting it builds a bootdisk with the values below. |
| `BOARD_SERIAL` | | Board serial number (MLB). |
| `UUID` | | System UUID. |
| `MAC_ADDRESS` | `52:54:00:09:49:17` | Guest MAC address, also the ROM with serial numbers. |
| `APPLEID_PATCH` | `false` | `true` hides the VM from Apple ID, iMessage and iCloud with a kernel patch. See [Apple ID login](../FAQ.md#apple-id-login). |
| `WIDTH` | `1920` | Screen width. |
| `HEIGHT` | `1080` | Screen height. A size OVMF doesn't offer, such as `1234x567`, falls back to 1280x800. |
| `NETWORKING` | `virtio-net-pci` | QEMU network device. `vmxnet3` for High Sierra and older, `e1000-82545em` if the network is slow. |
| `PORTS` | `10022:22,5900` | Forwarded ports, comma-separated: `PORT` or `CONTAINER:GUEST`, with an optional `/udp`. See [Ports](#ports). |
| `AUDIO_DRIVER` | `alsa` | QEMU `-audiodev` backend. `none` turns audio off. |
| `DISPLAY` | `:0.0` | X11 display for the QEMU window. |
| `QEMU_ARGS` | | Extra QEMU arguments, split on spaces. |

USB devices, extra disks and shared folders go through QEMU arguments in `QEMU_ARGS`. The [FAQ](../FAQ.md#usb-devices) has recipes.

## The data directory

The container keeps everything it writes in `/data`:

| File | What it is |
|---|---|
| `disk.qcow2` | The macOS disk, created on first start. |
| `installer.img` | The recovery image, downloaded on first start. Delete it to download another `MACOS_VERSION`. |
| `ovmf-vars.fd` | UEFI variables, such as boot order. |
| `serials.env` | Your serial numbers, see [Serial numbers](#serial-numbers). |
| `config.plist` | Optional. An OpenCore config to boot with instead of OSX-KVM's. |
| `bootdisk.qcow2` | The bootdisk built from your serial numbers, `config.plist`, `APPLEID_PATCH` or resolution, rebuilt at every start. |

The container starts as root, gives `/data`, `DISK_PATH` and `INSTALLER_PATH` to its `alcatraz` user (uid 1000), and runs QEMU as that user. A host directory owned by another user works, and ends up owned by uid 1000.

Without a mount, `/data` is an anonymous Docker volume that `docker rm -v` deletes. To copy it out of such a container, see [Extract the virtual disk](../FAQ.md#extract-the-virtual-disk).

## Ports

QEMU forwards the ports listed in `PORTS`, as `PORT` or `CONTAINER:GUEST` with an optional `/udp`. The default, `10022:22,5900`, forwards container port 10022 to guest port 22 for SSH and port 5900 for Screen Sharing. Setting `PORTS` replaces the default, so keep those two in the list if you need them, and publish each container port:

```bash
    -e PORTS=10022:22,5900,10023:80,10043:443 \
    -p 10023:10023 \
    -p 10043:10043 \
```

With these flags, a web server on guest port 80 answers on host port 10023.

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
