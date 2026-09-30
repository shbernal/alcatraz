#!/bin/bash
# alcatraz: macOS in a container
# https://github.com/shbernal/alcatraz
# Hard fork of Docker-OSX by Sick.Codes (https://github.com/sickcodes/Docker-OSX)
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Starts the macOS VM. Every setting comes from the environment, with the
# defaults set in the Dockerfile; entrypoint.sh picks BOOTDISK.
set -euxo pipefail

# RAM is in GB: RAM=max takes all of the host's memory, RAM=half half of it.
mem_total_kb() { head -n1 /proc/meminfo | tr -dc '[:digit:]'; }
case "${RAM}" in
    max) RAM="$(( $(mem_total_kb) / 1048576 ))" ;;
    half) RAM="$(( $(mem_total_kb) / 2097152 ))" ;;
esac

# BOOT_PICKER=false boots straight into the disk, without the installer attached.
install_media=()
if [[ "${BOOT_PICKER}" == true ]]; then
    install_media=(
        -device "ide-hd,bus=sata.3,drive=InstallMedia"
        -drive "id=InstallMedia,if=none,file=${INSTALLER_PATH},format=${INSTALLER_FORMAT}"
    )
fi

# PORTS is a comma-separated list of PORT, HOST:GUEST, either with an
# optional /udp.
forwards=""
IFS=, read -ra port_list <<< "${PORTS}"
for port in "${port_list[@]}"; do
    protocol=tcp
    [[ "${port}" == */udp ]] && protocol=udp
    port="${port%/*}"
    forwards+=",hostfwd=${protocol}::${port%%:*}-:${port#*:}"
done

# QEMU_ARGS is left unquoted: it carries any number of QEMU arguments.
# shellcheck disable=SC2086
exec qemu-system-x86_64 -m "${RAM}G" \
    -cpu "${CPU_MODEL},${CPU_FLAGS}" \
    -machine "q35,accel=${ACCEL}" \
    -smp "${CPUS},cores=${CORES}" \
    -device qemu-xhci,id=xhci \
    -device usb-kbd,bus=xhci.0 -device usb-tablet,bus=xhci.0 \
    -device 'isa-applesmc,osk=ourhardworkbythesewordsguardedpleasedontsteal(c)AppleComputerInc' \
    -drive if=pflash,format=raw,readonly=on,file=/opt/osx-kvm/OVMF_CODE_4M.fd \
    -drive if=pflash,format=raw,file=/data/ovmf-vars.fd \
    -smbios type=2 \
    -audiodev "${AUDIO_DRIVER},id=hda" -device ich9-intel-hda -device hda-duplex,audiodev=hda \
    -device ich9-ahci,id=sata \
    -drive "id=OpenCoreBoot,if=none,snapshot=on,format=qcow2,file=${BOOTDISK}" \
    -device ide-hd,bus=sata.2,drive=OpenCoreBoot \
    "${install_media[@]}" \
    -drive "id=MacHDD,if=none,file=${DISK_PATH},format=${DISK_FORMAT}" \
    -device ide-hd,bus=sata.4,drive=MacHDD \
    -netdev "user,id=net0,hostfwd=tcp::${INTERNAL_SSH_PORT}-:22,hostfwd=tcp::${SCREEN_SHARE_PORT}-:5900${forwards}" \
    -device "${NETWORKING},netdev=net0,id=net0,mac=${MAC_ADDRESS}" \
    -monitor stdio \
    -boot menu=on \
    -device vmware-svga \
    ${QEMU_ARGS}
