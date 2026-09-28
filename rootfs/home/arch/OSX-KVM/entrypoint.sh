#!/bin/bash
# Container start: fetch the installer if missing, prepare the bootdisk, start
# sshd, then hand over to Launch.sh.
set -euo pipefail
cd /home/arch/OSX-KVM

if [[ ! -e "${BASESYSTEM_IMAGE:-BaseSystem.img}" ]]; then
    printf '%s\n' "No BaseSystem.img available, downloading ${SHORTNAME}"
    make
    qemu-img convert BaseSystem.dmg -O qcow2 -p -c "${BASESYSTEM_IMAGE:-BaseSystem.img}"
    rm ./BaseSystem.dmg
fi

# Any of these may be unset or missing, e.g. when no sound device is passed.
sudo touch /dev/kvm /dev/snd "${IMAGE_PATH}" "${BOOTDISK}" "${ENV}" 2>/dev/null || true
sudo chown -R "$(id -u):$(id -g)" /dev/kvm /dev/snd "${IMAGE_PATH}" "${BOOTDISK}" "${ENV}" 2>/dev/null || true

if [[ "${NOPICKER}" == true ]]; then
    export BOOTDISK="${BOOTDISK:-/home/arch/OSX-KVM/OpenCore/OpenCore-nopicker.qcow2}"
else
    export BOOTDISK="${BOOTDISK:-/home/arch/OSX-KVM/OpenCore/OpenCore.qcow2}"
fi

if [[ "${GENERATE_UNIQUE}" == true ]]; then
    ./serial/generate-unique-machine-values.sh \
        --count 1 \
        --tsv ./serial.tsv \
        --width "${WIDTH:-1920}" \
        --height "${HEIGHT:-1080}" \
        --output-env "${ENV:-/env}"
fi

if [[ "${GENERATE_UNIQUE}" == true || "${GENERATE_SPECIFIC}" == true ]]; then
    # With GENERATE_SPECIFIC, the serials come from ENV if it exists,
    # otherwise from the environment.
    # shellcheck disable=SC1090
    source "${ENV:-/env}" 2>/dev/null || true
    if [[ "${MASTER_PLIST_URL}" ]]; then
        curl -fL -o ./serial.config.plist "${MASTER_PLIST_URL}"
    else
        ./opencore-config.py > ./serial.config.plist
    fi
    ./serial/generate-specific-bootdisk.sh \
        --master-plist ./serial.config.plist \
        --model "${DEVICE_MODEL:-}" \
        --serial "${SERIAL:-}" \
        --board-serial "${BOARD_SERIAL:-}" \
        --uuid "${UUID:-}" \
        --mac-address "${MAC_ADDRESS:-}" \
        --width "${WIDTH:-1920}" \
        --height "${HEIGHT:-1080}" \
        --output-bootdisk "${BOOTDISK}"
fi

./enable-ssh.sh
exec ./Launch.sh
