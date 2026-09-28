#!/bin/bash
# Starts the macOS VM. Every setting comes from the environment, with the
# defaults set in the Dockerfile.
set -euxo pipefail

sudo chown "$(id -u):$(id -g)" /dev/kvm 2>/dev/null || true
sudo chown -R "$(id -u):$(id -g)" /dev/snd 2>/dev/null || true

# RAM is in GB: RAM=max takes all of the host's memory, RAM=half half of it.
mem_total_kb() { head -n1 /proc/meminfo | tr -dc '[:digit:]'; }
case "${RAM:-4}" in
    max) RAM="$(( $(mem_total_kb) / 1000000 ))" ;;
    half) RAM="$(( $(mem_total_kb) / 2000000 ))" ;;
esac

# NOPICKER=true boots straight into the disk, without the installer attached.
install_media=()
if [[ "${NOPICKER:-false}" != true ]]; then
    install_media=(
        -device "ide-hd,bus=sata.3,drive=InstallMedia"
        -drive "id=InstallMedia,if=none,file=/home/arch/OSX-KVM/BaseSystem.img,format=${BASESYSTEM_FORMAT:-qcow2}"
    )
fi

# ADDITIONAL_PORTS and EXTRA are left unquoted: EXTRA carries any number of
# QEMU arguments, and both may be empty.
# shellcheck disable=SC2086
exec qemu-system-x86_64 -m "${RAM:-4}000" \
    -cpu "${CPU:-Skylake-Client,-hle,-rtm},${CPUID_FLAGS:-kvm=on,vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on,+ssse3,+sse4.2,+popcnt,+avx,+aes,+xsave,+xsaveopt,check,}${BOOT_ARGS:-}" \
    -machine "q35,${KVM-accel=kvm:tcg}" \
    -smp "${CPU_STRING:-${SMP:-4},cores=${CORES:-4}}" \
    -device qemu-xhci,id=xhci \
    -device usb-kbd,bus=xhci.0 -device usb-tablet,bus=xhci.0 \
    -device 'isa-applesmc,osk=ourhardworkbythesewordsguardedpleasedontsteal(c)AppleComputerInc' \
    -drive if=pflash,format=raw,readonly=on,file=/home/arch/OSX-KVM/OVMF_CODE_4M.fd \
    -drive if=pflash,format=raw,file=/home/arch/OSX-KVM/OVMF_VARS-1920x1080.fd \
    -smbios type=2 \
    -audiodev "${AUDIO_DRIVER:-alsa},id=hda" -device ich9-intel-hda -device hda-duplex,audiodev=hda \
    -device ich9-ahci,id=sata \
    -drive "id=OpenCoreBoot,if=none,snapshot=on,format=qcow2,file=${BOOTDISK:-/home/arch/OSX-KVM/OpenCore/OpenCore.qcow2}" \
    -device ide-hd,bus=sata.2,drive=OpenCoreBoot \
    "${install_media[@]}" \
    -drive "id=MacHDD,if=none,file=${IMAGE_PATH:-/home/arch/OSX-KVM/mac_hdd_ng.img},format=${IMAGE_FORMAT:-qcow2}" \
    -device ide-hd,bus=sata.4,drive=MacHDD \
    -netdev user,id=net0,hostfwd=tcp::${INTERNAL_SSH_PORT:-10022}-:22,hostfwd=tcp::${SCREEN_SHARE_PORT:-5900}-:5900,${ADDITIONAL_PORTS:-} \
    -device "${NETWORKING:-virtio-net-pci},netdev=net0,id=net0,mac=${MAC_ADDRESS:-52:54:00:09:49:17}" \
    -monitor stdio \
    -boot menu=on \
    -device vmware-svga \
    ${EXTRA:-}
