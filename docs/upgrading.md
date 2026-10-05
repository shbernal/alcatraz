# Upgrading from 1.x or Docker-OSX

2.0 moved everything a container writes to `/data` and renamed most settings. To boot an existing disk, put it in a directory as `disk.qcow2` and mount that directory:

```bash
mkdir mac && mv mac_hdd_ng.img mac/disk.qcow2
docker run ... -v ./mac:/data ghcr.io/shbernal/alcatraz:latest
```

For a disk still inside an old container, `docker cp <container-id>:/home/arch/OSX-KVM/mac_hdd_ng.img mac/disk.qcow2`. Add `-e INSTALLER=false`, or the installer is downloaded again on first start.

## Renamed settings

| 1.x and Docker-OSX | 2.0 |
|---|---|
| `SHORTNAME` | `MACOS_VERSION` |
| `IMAGE_PATH`, `IMAGE_FORMAT` | `DISK_PATH`, `DISK_FORMAT` (default `/data/disk.qcow2`) |
| `BASESYSTEM_IMAGE`, `BASESYSTEM_FORMAT` | `INSTALLER_PATH`, `INSTALLER_FORMAT` |
| `NOPICKER=true` | `INSTALLER=false` and `BOOT_PICKER=false` |
| `SMP` | `CPUS` |
| `CPU_STRING` | `CPUS` and `CORES` |
| `CPU` | `CPU_MODEL` |
| `CPUID_FLAGS`, `BOOT_ARGS` | `CPU_FLAGS` |
| `KVM=accel=kvm:tcg` | `ACCEL=kvm:tcg` |
| `EXTRA` | `QEMU_ARGS` |
| `ADDITIONAL_PORTS=hostfwd=tcp::23-:23,` | `PORTS=10022:22,5900,23` |
| `INTERNAL_SSH_PORT`, `SCREEN_SHARE_PORT` | `PORTS` |
| `GENERATE_UNIQUE=true` | `SERIALS=random` |
| `GENERATE_SPECIFIC=true` with `ENV=/env` | `/data/serials.env` |
| `GENERATE_SPECIFIC=true` with `SERIAL=…` | `SERIAL=…` |
| `MASTER_PLIST_URL` | `/data/config.plist`, without `{{…}}` placeholders |
| `/home/arch/OSX-KVM` | `/opt/osx-kvm` (upstream) and `/opt/alcatraz` (scripts) |
| `Launch.sh` | `/opt/alcatraz/launch.sh` |
| user `arch` | user `alcatraz` |

## Removed

The container's own SSH server is gone; use `docker exec -it <container> bash` for a shell in the container. From Docker-OSX, the `:naked`, `:auto` and VNC images are gone; mount your disk and add `-e INSTALLER=false -e BOOT_PICKER=false` if you relied on `:naked`'s default.

## Old virtual hardware

Disks installed with Docker-OSX's older defaults, a `Penryn` CPU and a `vmxnet3` network card, boot on the current ones. To keep the old virtual hardware for such a disk anyway:

```bash
    -e CPU_MODEL=Penryn \
    -e CPU_FLAGS='vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on,+ssse3,+sse4.2,+popcnt,+avx,+aes,+xsave,+xsaveopt,check' \
    -e NETWORKING=vmxnet3 \
```
