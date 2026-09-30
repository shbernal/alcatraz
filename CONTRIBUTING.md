# Contributing

Issues and pull requests are welcome, including fully AI-generated ones. Say which harness and model wrote it (for example "Claude Code, Claude Opus 5.5").

## Layout

- [Dockerfile](Dockerfile) builds the image: Arch Linux, QEMU, OVMF, a pinned OSX-KVM in `/opt/osx-kvm`, `macserial` built from a pinned OpenCorePkg release, and the no-picker bootdisk.
- [rootfs/opt/alcatraz](rootfs/opt/alcatraz) holds the scripts the container runs, at the path they take in the image. `entrypoint.sh` starts as root, hands `/data` and the KVM and sound devices to the `alcatraz` user, and continues as that user: it prepares `/data` and the bootdisk and hands over to `launch.sh`, which starts QEMU. `build-bootdisk.sh` and `opencore-config.py` build bootdisks, at build time and at start for serial numbers, `config.plist` or `APPLEID_PATCH`: a GPT disk with one FAT EFI partition, written with mtools. `generate-serials.sh` writes `/data/serials.env` for `SERIALS=random`, offline.
- [tests](tests) holds the checks CI runs, see [Testing](#testing).

In the image, `/opt/osx-kvm` stays as fetched, `/opt/alcatraz` is read-only, and everything a container writes goes to `/data`.

## Building

```bash
docker build -t alcatraz .
```

The build pins OSX-KVM to a commit with `ARG OSX_KVM_REF`. OSX-KVM supplies the firmware, the OpenCore bootdisk and its config, and the recovery download script, so a bump can break booting. After changing the commit, build, then boot an existing disk and a fresh install.

`archlinux:base` is not pinned. Pass its digest as `--build-arg BASE_DIGEST=sha256:…` to record it in the `org.opencontainers.image.base.digest` label; the release workflow does this.

## Testing

CI runs these on every push and pull request, and publishes the image only if they pass:

```bash
shellcheck rootfs/opt/alcatraz/*.sh tests/*.sh

# the OpenCore config and the QEMU command line, no VM needed
docker run --rm -v ./tests:/tests:ro --entrypoint python3 alcatraz /tests/offline.py

# boots headless until OpenCore draws its picker, saves smoke-test.png
tests/smoke-test.sh alcatraz
tests/smoke-test.sh alcatraz -e BOOT_PICKER=false
tests/smoke-test.sh alcatraz -e DEVICE_MODEL=iMacPro1,1 -e SERIAL=… -e BOARD_SERIAL=… -e UUID=…
```

The smoke test needs `/dev/kvm` and stops at the picker: it downloads no recovery image and installs nothing. Installing and booting macOS stays a manual test, done for `OSX_KVM_REF` bumps.
