#!/bin/bash
# alcatraz: macOS in a container
# https://github.com/shbernal/alcatraz
# Hard fork of Docker-OSX by Sick.Codes (https://github.com/sickcodes/Docker-OSX)
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Container start: as root, hand /data and the KVM and sound devices to the
# alcatraz user, then, as alcatraz, prepare
# everything under /data (disk, installer, firmware variables, serials,
# bootdisk) and hand over to launch.sh.
set -euo pipefail

if (( EUID == 0 )); then
    chown alcatraz: /data "${DISK_PATH}" "${INSTALLER_PATH}" 2>/dev/null || true
    # The device nodes are the container's own, so this leaves the host's alone.
    chown -R alcatraz: /dev/kvm /dev/snd 2>/dev/null || true
    HOME=/home/alcatraz exec setpriv --reuid=alcatraz --regid=alcatraz --init-groups --inh-caps=-all "$0"
fi

if [[ "${INSTALLER}" == true && ! -e "${INSTALLER_PATH}" ]]; then
    printf '%s\n' "No installer at ${INSTALLER_PATH}, downloading macOS ${MACOS_VERSION}"
    download="$(mktemp -d)"
    (cd "${download}" && /opt/osx-kvm/fetch-macOS-v2.py --shortname="${MACOS_VERSION}")
    compress=()
    [[ "${INSTALLER_FORMAT}" == qcow2 ]] && compress=(-c)
    qemu-img convert -p "${compress[@]}" -O "${INSTALLER_FORMAT}" "${download}/BaseSystem.dmg" "${INSTALLER_PATH}"
    rm -rf "${download}"
fi

if [[ ! -e "${DISK_PATH}" ]]; then
    qemu-img create -f "${DISK_FORMAT}" "${DISK_PATH}" "${DISK_SIZE}"
fi

# UEFI variables live next to the disk, so boot settings persist with it.
if [[ ! -e /data/ovmf-vars.fd ]]; then
    cp /opt/osx-kvm/OVMF_VARS-1920x1080.fd /data/ovmf-vars.fd
fi

# Serials passed in the environment win; otherwise /data/serials.env, created
# first if SERIALS=random.
if [[ -z "${SERIAL:-}" ]]; then
    # shellcheck disable=SC2153 # SERIALS is set in the Dockerfile
    if [[ "${SERIALS}" == random && ! -e /data/serials.env ]]; then
        /opt/alcatraz/generate-serials.sh /data/serials.env
    fi
    if [[ -e /data/serials.env ]]; then
        # shellcheck disable=SC1091
        source /data/serials.env
    fi
fi

# The prebuilt bootdisks carry OSX-KVM's config at 1920x1080; anything else
# needs a bootdisk of its own.
custom_bootdisk() {
    [[ -n "${SERIAL:-}" || -e /data/config.plist || "${APPLEID_PATCH}" == true ||
       "${WIDTH}x${HEIGHT}" != 1920x1080 ]]
}

if [[ -z "${BOOTDISK}" ]]; then
    if custom_bootdisk; then
        if [[ -n "${SERIAL:-}" ]]; then
            : "${DEVICE_MODEL:?SERIAL also needs DEVICE_MODEL}" \
              "${BOARD_SERIAL:?SERIAL also needs BOARD_SERIAL}" \
              "${UUID:?SERIAL also needs UUID}"
        fi
        BOOTDISK=/data/bootdisk.qcow2
        /opt/alcatraz/build-bootdisk.sh "${BOOTDISK}"
    elif [[ "${BOOT_PICKER}" == true ]]; then
        BOOTDISK=/opt/alcatraz/picker.qcow2
    else
        BOOTDISK=/opt/alcatraz/nopicker.qcow2
    fi
    export BOOTDISK
fi

exec /opt/alcatraz/launch.sh
