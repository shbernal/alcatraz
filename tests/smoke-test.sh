#!/bin/bash
# alcatraz: macOS in a container
# https://github.com/shbernal/alcatraz
# SPDX-License-Identifier: GPL-3.0-or-later
#
# smoke-test.sh <image> [docker run arguments...]
# Boots the image headless until OpenCore draws its picker, and saves the
# screen to smoke-test.png, or to SMOKE_SCREENSHOT. An empty installer stands in for the recovery
# image, so nothing is downloaded. Extra arguments go to docker run, for
# example -e SERIAL=… to test a bootdisk built at start (not QEMU_ARGS, which
# the test sets).
set -euo pipefail
image="$1"
shift
timeout="${SMOKE_TIMEOUT:-300}"
screenshot="${SMOKE_SCREENSHOT:-smoke-test.png}"
name="alcatraz-smoke-$$"

cleanup() {
    docker rm -f "${name}" >/dev/null 2>&1 || true
    docker volume rm "${name}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker volume create "${name}" >/dev/null
docker run --rm -v "${name}:/data" --entrypoint qemu-img "${image}" \
    create -q -f qcow2 /data/installer.img 1G
docker run -di --name "${name}" --device /dev/kvm -v "${name}:/data" \
    -e QEMU_ARGS="-display none -qmp unix:/tmp/qmp.sock,server=on,wait=off" \
    "$@" "${image}" >/dev/null

# Screendump through QMP until the screen holds still and shows more than a
# few colours: a blank or text console has too few, and OVMF's splash moves
# its progress bar.
screen() {
    docker exec -i "${name}" python3 - <<'EOF'
import hashlib, json, socket
s = socket.socket(socket.AF_UNIX); s.connect("/tmp/qmp.sock"); f = s.makefile("rw")
f.readline()
for c in ({"execute": "qmp_capabilities"},
          {"execute": "screendump", "arguments": {"filename": "/tmp/shot.ppm"}},
          {"execute": "screendump", "arguments": {"filename": "/tmp/shot.png", "format": "png"}}):
    f.write(json.dumps(c) + "\n"); f.flush()
    reply = json.loads(f.readline())
    if "error" in reply:
        raise SystemExit(reply["error"]["desc"])
# QEMU writes the header as "P6\n<width> <height>\n255\n"
pixels = open("/tmp/shot.ppm", "rb").read().split(b"\n", 3)[3]
print(len({pixels[i:i + 3] for i in range(0, len(pixels), 3 * 97)}), hashlib.md5(pixels).hexdigest())
EOF
}

colours=0 last="" up=false
for (( waited = 0; waited < timeout; waited += 5 )); do
    if ! docker inspect -f '{{.State.Running}}' "${name}" | grep -q true; then
        docker logs "${name}" | tail -n 30
        echo "smoke test: the container stopped" >&2
        exit 1
    fi
    if docker exec "${name}" test -S /tmp/qmp.sock && shot="$(screen 2>/dev/null)"; then
        colours="${shot% *}"
        if (( colours > 20 )) && [[ "${shot}" == "${last}" ]]; then
            up=true
            break
        fi
        last="${shot}"
    fi
    sleep 5
done
docker cp -q "${name}:/tmp/shot.png" "${screenshot}" 2>/dev/null || true
if [[ "${up}" != true ]]; then
    docker logs "${name}" | tail -n 30
    echo "smoke test: no picker after ${timeout}s (${colours} colours on screen)" >&2
    exit 1
fi
echo "smoke test: OpenCore is up after ${waited}s (${colours} colours on screen), see ${screenshot}"
