# Contributing

Issues and pull requests are welcome, including fully AI-generated ones. Say which harness and model wrote it (for example "Claude Code, Claude Opus 5.5").

## Layout

- [Dockerfile](Dockerfile) builds the image: Arch Linux, QEMU, OVMF, a pinned OSX-KVM in `/opt/osx-kvm`, and the no-picker bootdisk.
- [rootfs/opt/alcatraz](rootfs/opt/alcatraz) holds the scripts the container runs, at the path they take in the image. `entrypoint.sh` prepares `/data` and the bootdisk and hands over to `launch.sh`, which starts QEMU. `build-bootdisk.sh` and `opencore-config.py` build bootdisks, at build time and for serial numbers.
- `vendor/osx-serial-generator/` holds scripts from [osx-serial-generator](https://github.com/sickcodes/osx-serial-generator) at 908b3d6, with the changes noted in their git history.
- [tools](tools) holds scripts users run on their own machines, not in the image.

In the image, `/opt/osx-kvm` stays as fetched, `/opt/alcatraz` is read-only, and everything a container writes goes to `/data`.

## Building

```bash
docker build -t alcatraz .
```

The build pins OSX-KVM to a commit with `ARG OSX_KVM_REF`. OSX-KVM supplies the firmware, the OpenCore bootdisk and its config, and the recovery download script, so a bump can break booting. After changing the commit, build, then boot an existing disk and a fresh install.

`archlinux:base-devel` is not pinned. Pass its digest as `--build-arg BASE_DIGEST=sha256:…` to record it in the `org.opencontainers.image.base.digest` label; the release workflow does this.

## Testing

`shellcheck rootfs/opt/alcatraz/*.sh` should stay clean.

To check a build boots without a display, run it headless with a QMP socket and take a screenshot:

```bash
docker run -di --name alcatraz-test --device /dev/kvm \
    -e QEMU_ARGS="-display none -qmp unix:/tmp/qmp.sock,server=on,wait=off" \
    alcatraz

# once `docker logs alcatraz-test` shows the qemu command line
docker exec alcatraz-test python3 -c '
import json, socket
s = socket.socket(socket.AF_UNIX); s.connect("/tmp/qmp.sock"); f = s.makefile("rw")
f.readline()
for c in ({"execute": "qmp_capabilities"}, {"execute": "screendump", "arguments": {"filename": "/tmp/shot.png", "format": "png"}}):
    f.write(json.dumps(c) + "\n"); f.flush(); print(f.readline())
'
docker cp alcatraz-test:/tmp/shot.png .
```

A fresh container downloads the recovery image first (about 900 MB for Tahoe), so the OpenCore picker shows up a few minutes in.
