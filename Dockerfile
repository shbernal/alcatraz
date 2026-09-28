#!/usr/bin/docker
#     ____             __             ____  ______  __
#    / __ \____  _____/ /_____  _____/ __ \/ ___/ |/ /
#   / / / / __ \/ ___/ //_/ _ \/ ___/ / / /\__ \|   /
#  / /_/ / /_/ / /__/ ,< /  __/ /  / /_/ /___/ /   |
# /_____/\____/\___/_/|_|\___/_/   \____//____/_/|_|
#
# Title:            Docker-OSX (Mac on Docker)
# Author:           Sick.Codes https://twitter.com/sickcodes
# Version:          6.0
# License:          GPLv3+
# Repository:       https://github.com/sickcodes/Docker-OSX
# Website:          https://sick.codes
#
# All credits for OSX-KVM and the rest at @Kholia's repo: https://github.com/kholia/osx-kvm
# OpenCore support go to https://github.com/Leoyzen/KVM-Opencore
# and https://github.com/thenickdude/KVM-Opencore/
#
# This Dockerfile automates the installation of Docker-OSX
# It will build a 200GB container. You can change the size using build arguments.
# This Dockerfile builds on top of the work done by Dhiru Kholia, and many others.
#
# Build:
#
#       docker build -t docker-osx .
#
# Basic Run:
#
#       docker run --device /dev/kvm --device /dev/snd -v /tmp/.X11-unix:/tmp/.X11-unix -e "DISPLAY=${DISPLAY:-:0.0}" sickcodes/docker-osx:latest
#
# Run with SSH:
#
#       docker run --device /dev/kvm --device /dev/snd -e RAM=6 -p 50922:10022 -v /tmp/.X11-unix:/tmp/.X11-unix -e "DISPLAY=${DISPLAY:-:0.0}" sickcodes/docker-osx:latest
#       # ssh fullname@localhost -p 50922
#
# Optargs:
#
#       -v $PWD/disk.img:/image
#       -e RAM=5
#       -e SMP=4
#       -e CORES=4
#       -e EXTRA=
#       -e INTERNAL_SSH_PORT=10022
#       -e MAC_ADDRESS=
#
# Extra QEMU args:
#
#       docker run ... -e EXTRA="-usb -device usb-host,hostbus=1,hostaddr=8" ...
#       # you will also need to pass the device to the container

FROM archlinux:base-devel
LABEL maintainer='https://twitter.com/sickcodes <https://sick.codes>'

SHELL ["/bin/bash", "-c"]

ARG PARALLEL_DOWNLOADS=30

RUN perl -i -p -e s/^\#Color/Color$'\n'ParallelDownloads\ =\ ${PARALLEL_DOWNLOADS:=30}/g /etc/pacman.conf 

RUN tee /etc/pacman.d/mirrorlist <<< 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' \
    && tee -a /etc/pacman.d/mirrorlist <<< 'Server = http://mirror.rackspace.com/archlinux/$repo/os/$arch' \
    && tee -a /etc/pacman.d/mirrorlist <<< 'Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch'

# Fixes issue with invalid GPG keys: update the archlinux-keyring package to get the latest keys, then remove and regenerate gnupg keys
RUN pacman -Sy archlinux-keyring --noconfirm \
    && rm -rf /etc/pacman.d/gnupg \
    && pacman-key --init \
    && pacman-key --populate archlinux

RUN pacman -Syu git zip vim nano alsa-utils openssh --noconfirm \
    && ln -s /bin/vim /bin/vi \
    && useradd arch -p arch \
    && tee -a /etc/sudoers <<< 'arch ALL=(ALL) NOPASSWD: ALL' \
    && mkdir -p /home/arch \
    && chown arch:arch /home/arch

# allow ssh to container
RUN mkdir -p -m 700 /root/.ssh

WORKDIR /root/.ssh
RUN touch authorized_keys \
    && chmod 644 authorized_keys

WORKDIR /etc/ssh
RUN tee -a sshd_config <<< 'AllowTcpForwarding yes' \
    && tee -a sshd_config <<< 'PermitTunnel yes' \
    && tee -a sshd_config <<< 'X11Forwarding yes' \
    && tee -a sshd_config <<< 'PasswordAuthentication yes' \
    && tee -a sshd_config <<< 'PermitRootLogin yes' \
    && tee -a sshd_config <<< 'PubkeyAuthentication yes' \
    && tee -a sshd_config <<< 'HostKey /etc/ssh/ssh_host_rsa_key' \
    && tee -a sshd_config <<< 'HostKey /etc/ssh/ssh_host_ecdsa_key' \
    && tee -a sshd_config <<< 'HostKey /etc/ssh/ssh_host_ed25519_key'

USER arch

# download OSX-KVM for the submodules
RUN git clone --recurse-submodules --depth 1 https://github.com/kholia/OSX-KVM.git /home/arch/OSX-KVM

# enable ssh
# docker exec .... ./enable-ssh.sh
WORKDIR /home/arch/OSX-KVM

RUN touch enable-ssh.sh \
    && chmod +x ./enable-ssh.sh \
    && tee -a enable-ssh.sh <<< '[[ -f /etc/ssh/ssh_host_rsa_key ]] || \' \
    && tee -a enable-ssh.sh <<< '[[ -f /etc/ssh/ssh_host_ecdsa_key ]] || \' \
    && tee -a enable-ssh.sh <<< '[[ -f /etc/ssh/ssh_host_ed25519_key ]] || \' \
    && tee -a enable-ssh.sh <<< 'sudo /usr/bin/ssh-keygen -A' \
    && tee -a enable-ssh.sh <<< 'nohup sudo /usr/bin/sshd -D &'

# QEMU CONFIGURATOR
# set optional ram at runtime -e RAM=16
# set optional cores at runtime -e SMP=4 -e CORES=2
# add any additional commands in QEMU cli format -e EXTRA="-usb -device usb-host,hostbus=1,hostaddr=8"

# default env vars, RUNTIME ONLY, not for editing in build time.

RUN sudo pacman -Syu bc qemu-desktop edk2-ovmf wget --overwrite '*' --noconfirm \
    && yes | sudo pacman -Scc

ARG LINUX=true

# required to use libguestfs inside a docker container, to create bootdisks for docker-osx on-the-fly
# reminder this is what makes :naked image larger than expected
RUN if [[ "${LINUX}" == true ]]; then \
        sudo pacman -Syu linux linux-headers archlinux-keyring guestfs-tools mkinitcpio --noconfirm \
        && libguestfs-test-tool \
        && rm -rf /var/tmp/.guestfs-* \
        && yes | sudo pacman -Scc \
    ; fi

# optional --build-arg to change branches for testing
ARG BRANCH=master
ARG REPO='https://github.com/sickcodes/Docker-OSX.git'
RUN git clone --recurse-submodules --depth 1 --branch "${BRANCH:=master}" "${REPO:=https://github.com/sickcodes/Docker-OSX.git}"

# The serial generator looks for opencore-image-ng.sh here before downloading it.
# Right after mkfs, mount often misses the new FAT filesystem and only tries the
# filesystems the libguestfs appliance has loaded, so load vfat first.
RUN sed -e '/^fish mount \/dev\/sda2 \//i fish modprobe vfat' \
        ./Docker-OSX/osx-serial-generator/opencore-image-ng.sh > ./opencore-image-ng.sh \
    && grep -q '^fish modprobe vfat' ./opencore-image-ng.sh \
    && chmod +x ./opencore-image-ng.sh

RUN touch Launch.sh \
    && chmod +x ./Launch.sh \
    && tee -a Launch.sh <<< '#!/bin/bash' \
    && tee -a Launch.sh <<< 'set -eux' \
    && tee -a Launch.sh <<< 'sudo chown    $(id -u):$(id -g) /dev/kvm 2>/dev/null || true' \
    && tee -a Launch.sh <<< 'sudo chown -R $(id -u):$(id -g) /dev/snd 2>/dev/null || true' \
    && tee -a Launch.sh <<< '[[ "${RAM}" = max ]] && export RAM="$(("$(head -n1 /proc/meminfo | tr -dc "[:digit:]") / 1000000"))"' \
    && tee -a Launch.sh <<< '[[ "${RAM}" = half ]] && export RAM="$(("$(head -n1 /proc/meminfo | tr -dc "[:digit:]") / 2000000"))"' \
    && tee -a Launch.sh <<< 'exec qemu-system-x86_64 -m ${RAM:-4}000 \' \
    && tee -a Launch.sh <<< '-cpu ${CPU:-Skylake-Client,-hle,-rtm},${CPUID_FLAGS:-kvm=on,vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on,+ssse3,+sse4.2,+popcnt,+avx,+aes,+xsave,+xsaveopt,check,}${BOOT_ARGS} \' \
    && tee -a Launch.sh <<< '-machine q35,${KVM-"accel=kvm:tcg"} \' \
    && tee -a Launch.sh <<< '-smp ${CPU_STRING:-${SMP:-4},cores=${CORES:-4}} \' \
    && tee -a Launch.sh <<< '-device qemu-xhci,id=xhci \' \
    && tee -a Launch.sh <<< '-device usb-kbd,bus=xhci.0 -device usb-tablet,bus=xhci.0 \' \
    && tee -a Launch.sh <<< '-device isa-applesmc,osk=ourhardworkbythesewordsguardedpleasedontsteal\(c\)AppleComputerInc \' \
    && tee -a Launch.sh <<< '-drive if=pflash,format=raw,readonly=on,file=/home/arch/OSX-KVM/OVMF_CODE_4M.fd \' \
    && tee -a Launch.sh <<< '-drive if=pflash,format=raw,file=/home/arch/OSX-KVM/OVMF_VARS-1920x1080.fd \' \
    && tee -a Launch.sh <<< '-smbios type=2 \' \
    && tee -a Launch.sh <<< '-audiodev ${AUDIO_DRIVER:-alsa},id=hda -device ich9-intel-hda -device hda-duplex,audiodev=hda \' \
    && tee -a Launch.sh <<< '-device ich9-ahci,id=sata \' \
    && tee -a Launch.sh <<< '-drive id=OpenCoreBoot,if=none,snapshot=on,format=qcow2,file=${BOOTDISK:-/home/arch/OSX-KVM/OpenCore/OpenCore.qcow2} \' \
    && tee -a Launch.sh <<< '-device ide-hd,bus=sata.2,drive=OpenCoreBoot \' \
    && tee -a Launch.sh <<< '-device ide-hd,bus=sata.3,drive=InstallMedia \' \
    && tee -a Launch.sh <<< '-drive id=InstallMedia,if=none,file=/home/arch/OSX-KVM/BaseSystem.img,format=${BASESYSTEM_FORMAT:-qcow2} \' \
    && tee -a Launch.sh <<< '-drive id=MacHDD,if=none,file=${IMAGE_PATH:-/home/arch/OSX-KVM/mac_hdd_ng.img},format=${IMAGE_FORMAT:-qcow2} \' \
    && tee -a Launch.sh <<< '-device ide-hd,bus=sata.4,drive=MacHDD \' \
    && tee -a Launch.sh <<< '-netdev user,id=net0,hostfwd=tcp::${INTERNAL_SSH_PORT:-10022}-:22,hostfwd=tcp::${SCREEN_SHARE_PORT:-5900}-:5900,${ADDITIONAL_PORTS} \' \
    && tee -a Launch.sh <<< '-device ${NETWORKING:-virtio-net-pci},netdev=net0,id=net0,mac=${MAC_ADDRESS:-52:54:00:09:49:17} \' \
    && tee -a Launch.sh <<< '-monitor stdio \' \
    && tee -a Launch.sh <<< '-boot menu=on \' \
    && tee -a Launch.sh <<< '-device vmware-svga \' \
    && tee -a Launch.sh <<< '${EXTRA:-}'

# Writes OSX-KVM's OpenCore config with the serials from the environment, if set,
# and with the picker off if NOPICKER=true. Used for the nopicker bootdisk and by
# GENERATE_UNIQUE and GENERATE_SPECIFIC unless MASTER_PLIST_URL is set.
RUN touch opencore-config.py \
    && chmod +x ./opencore-config.py \
    && tee -a opencore-config.py <<< '#!/usr/bin/env python3' \
    && tee -a opencore-config.py <<< 'import os, plistlib, re, sys' \
    && tee -a opencore-config.py <<< 'with open("/home/arch/OSX-KVM/OpenCore/config.plist", "rb") as f:' \
    && tee -a opencore-config.py <<< '    config = plistlib.load(f)' \
    && tee -a opencore-config.py <<< 'if os.environ.get("SERIAL"):' \
    && tee -a opencore-config.py <<< '    generic = config["PlatformInfo"]["Generic"]' \
    && tee -a opencore-config.py <<< '    generic["SystemProductName"] = os.environ["DEVICE_MODEL"]' \
    && tee -a opencore-config.py <<< '    generic["SystemSerialNumber"] = os.environ["SERIAL"]' \
    && tee -a opencore-config.py <<< '    generic["MLB"] = os.environ["BOARD_SERIAL"]' \
    && tee -a opencore-config.py <<< '    generic["SystemUUID"] = os.environ["UUID"]' \
    && tee -a opencore-config.py <<< '    generic["ROM"] = bytes.fromhex(os.environ["MAC_ADDRESS"].replace(":", ""))' \
    && tee -a opencore-config.py <<< '    width, height = os.environ.get("WIDTH") or "1920", os.environ.get("HEIGHT") or "1080"' \
    && tee -a opencore-config.py <<< '    config["UEFI"]["Output"]["Resolution"] = f"{width}x{height}@32"' \
    && tee -a opencore-config.py <<< 'if os.environ.get("NOPICKER") == "true":' \
    && tee -a opencore-config.py <<< '    config["Misc"]["Boot"]["ShowPicker"] = False' \
    && tee -a opencore-config.py <<< '    config["Misc"]["Boot"]["Timeout"] = 0' \
    && tee -a opencore-config.py <<< '    # only list APFS and HFS volumes: with every volume, the bootdisk'"'"'s own EFI' \
    && tee -a opencore-config.py <<< '    # partition comes first, fails to boot, and OpenCore shows the picker anyway' \
    && tee -a opencore-config.py <<< '    config["Misc"]["Security"]["ScanPolicy"] = 0x1 | 0x100 | 0x200' \
    && tee -a opencore-config.py <<< '# the config names a kext that ships as MCEReporterDisabler.kext; without it' \
    && tee -a opencore-config.py <<< '# AppleIntelMCEReporter panics on iMacPro1,1 and MacPro models' \
    && tee -a opencore-config.py <<< 'for kext in config["Kernel"]["Add"]:' \
    && tee -a opencore-config.py <<< '    if kext["BundlePath"] == "AppleMCEReporterDisabler.kext" and not os.path.exists("/home/arch/OSX-KVM/OpenCore/EFI/OC/Kexts/AppleMCEReporterDisabler.kext"):' \
    && tee -a opencore-config.py <<< '        kext["BundlePath"] = "MCEReporterDisabler.kext"' \
    && tee -a opencore-config.py <<< '# keep <data> on one line like the original, plistlib wraps it' \
    && tee -a opencore-config.py <<< 'out = plistlib.dumps(config, sort_keys=False)' \
    && tee -a opencore-config.py <<< 'out = re.sub(rb"<data>(.*?)</data>", lambda m: b"<data>" + b"".join(m[1].split()) + b"</data>", out, flags=re.S)' \
    && tee -a opencore-config.py <<< 'sys.stdout.buffer.write(out)'

ENV USER=arch

# libguestfs verbose
ENV LIBGUESTFS_DEBUG=1
ENV LIBGUESTFS_TRACE=1

# OSX-KVM only ships OpenCore.qcow2, so build the NOPICKER=true bootdisk from the
# same config with the picker off. opencore-image-ng.sh takes EFI/ and
# startup.nsh from the current directory.
RUN cp -a ./OpenCore/EFI . \
    && echo 'fs0:\EFI\BOOT\BOOTx64.efi' > startup.nsh \
    && NOPICKER=true ./opencore-config.py > ./nopicker.config.plist \
    && ./opencore-image-ng.sh \
        --cfg ./nopicker.config.plist \
        --img ./OpenCore/OpenCore-nopicker.qcow2 \
    && rm -rf ./EFI ./startup.nsh ./nopicker.config.plist /var/tmp/.guestfs-*

#### SPECIAL RUNTIME ARGUMENTS BELOW
# env -e ADDITIONAL_PORTS with a comma
# for example, -e ADDITIONAL_PORTS=hostfwd=tcp::23-:23,
ENV ADDITIONAL_PORTS=

# since the Makefile uses raw, and raw uses the full disk amount
# we want to use a compressed qcow2
# ENV BASESYSTEM_FORMAT=raw
ENV BASESYSTEM_FORMAT=qcow2

# add additional QEMU boot arguments
ENV BOOT_ARGS=

ENV BOOTDISK=

# edit the CPU that is being emulated
ENV CPU=Skylake-Client,-hle,-rtm
ENV CPUID_FLAGS='kvm=on,vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on,+ssse3,+sse4.2,+popcnt,+avx,+aes,+xsave,+xsaveopt,check,'

ENV DISPLAY=:0.0

# Deprecated
ENV ENV=/env

# Boolean for generating a bootdisk with new random serials.
ENV GENERATE_UNIQUE=false

# Boolean for generating a bootdisk with specific serials.
ENV GENERATE_SPECIFIC=false

ENV IMAGE_PATH=/home/arch/OSX-KVM/mac_hdd_ng.img
ENV IMAGE_FORMAT=qcow2

ENV KVM='accel=kvm:tcg'

# A config.plist with {{SERIAL}}-style placeholders to use instead of OSX-KVM's own
# when generating a bootdisk, e.g. the templates in sickcodes/osx-serial-generator.
ENV MASTER_PLIST_URL=

# ENV NETWORKING=e1000-82545em
ENV NETWORKING=virtio-net-pci

# boolean for skipping the disk selection menu at in the boot process
ENV NOPICKER=false

# dynamic RAM options for runtime
ENV RAM=4
# ENV RAM=max
# ENV RAM=half

# The x and y coordinates for resolution.
# Must be used with either -e GENERATE_UNIQUE=true or -e GENERATE_SPECIFIC=true.
ENV WIDTH=1920
ENV HEIGHT=1080

VOLUME ["/tmp/.X11-unix"]

# check if /image is a disk image or a directory. This allows you to optionally use -v disk.img:/image
# NOPICKER is used to skip the disk selection screen
# GENERATE_UNIQUE is used to generate serial numbers on boot.
# /env is a file that you can generate and save using -v source.sh:/env
# the env file is a file that you can carry to the next container which will supply the serials numbers.
# GENERATE_SPECIFIC is used to either accept the env serial numbers OR you can supply using:
    # -e DEVICE_MODEL="iMacPro1,1" \
    # -e SERIAL="C02TW0WAHX87" \
    # -e BOARD_SERIAL="C027251024NJG36UE" \
    # -e UUID="5CCB366D-9118-4C61-A00A-E5BAF3BED451" \
    # -e MAC_ADDRESS="A8:5C:2C:9A:46:2F" \

# the output will be /bootdisk.
# /bootdisk is a useful persistent place to store the 15Mb serial number bootdisk.

# if you don't set any of the above:
# the default serial numbers are already contained in ./OpenCore/OpenCore.qcow2
# And the default serial numbers

# DMCA compliant download process
# If BaseSystem.img does not exist, download ${SHORTNAME}

# shortname default is below
ENV SHORTNAME=tahoe

ENV BASESYSTEM_IMAGE=BaseSystem.img

CMD ! [[ -e "${BASESYSTEM_IMAGE:-BaseSystem.img}" ]] \
        && printf '%s\n' "No BaseSystem.img available, downloading ${SHORTNAME}" \
        && make \
        && qemu-img convert BaseSystem.dmg -O qcow2 -p -c ${BASESYSTEM_IMAGE:-BaseSystem.img} \
        && rm ./BaseSystem.dmg \
    ; sudo touch /dev/kvm /dev/snd "${IMAGE_PATH}" "${BOOTDISK}" "${ENV}" 2>/dev/null || true \
    ; sudo chown -R $(id -u):$(id -g) /dev/kvm /dev/snd "${IMAGE_PATH}" "${BOOTDISK}" "${ENV}" 2>/dev/null || true \
    ; [[ "${NOPICKER}" == true ]] && { \
        sed -i '/^.*InstallMedia.*/d' Launch.sh \
        && export BOOTDISK="${BOOTDISK:=/home/arch/OSX-KVM/OpenCore/OpenCore-nopicker.qcow2}" \
    ; } \
    || export BOOTDISK="${BOOTDISK:=/home/arch/OSX-KVM/OpenCore/OpenCore.qcow2}" \
    ; [[ "${GENERATE_UNIQUE}" == true ]] && { \
        ./Docker-OSX/osx-serial-generator/generate-unique-machine-values.sh \
            --count 1 \
            --tsv ./serial.tsv \
            --width "${WIDTH:-1920}" \
            --height "${HEIGHT:-1080}" \
            --output-env "${ENV:=/env}" \
    || exit 1 ; } \
    ; [[ "${GENERATE_UNIQUE}" == true || "${GENERATE_SPECIFIC}" == true ]] && { \
            source "${ENV:=/env}" 2>/dev/null \
            ; if [[ "${MASTER_PLIST_URL}" ]]; then \
                curl -fL -o ./serial.config.plist "${MASTER_PLIST_URL}" \
            ; else \
                ./opencore-config.py > ./serial.config.plist \
            ; fi \
            && ./Docker-OSX/osx-serial-generator/generate-specific-bootdisk.sh \
            --master-plist ./serial.config.plist \
            --model "${DEVICE_MODEL}" \
            --serial "${SERIAL}" \
            --board-serial "${BOARD_SERIAL}" \
            --uuid "${UUID}" \
            --mac-address "${MAC_ADDRESS}" \
            --width "${WIDTH:-1920}" \
            --height "${HEIGHT:-1080}" \
            --output-bootdisk "${BOOTDISK:=/home/arch/OSX-KVM/OpenCore/OpenCore.qcow2}" \
    || exit 1 ; } \
    ; ./enable-ssh.sh && /bin/bash -c ./Launch.sh
