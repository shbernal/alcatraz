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

# archlinux:base-devel is a rolling tag. Pass the digest it resolved to, so a
# broken rebuild can be traced to its base.
ARG BASE_DIGEST
LABEL org.opencontainers.image.base.name=docker.io/library/archlinux:base-devel
LABEL org.opencontainers.image.base.digest=${BASE_DIGEST}
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

# OSX-KVM provides the firmware, the OpenCore bootdisk and its config, and the
# macOS download script. Bump the commit on purpose and test a boot.
ARG OSX_KVM_REF=4c378a4b5e0b219783683012bec680325eb40719
RUN git init -q /home/arch/OSX-KVM \
    && cd /home/arch/OSX-KVM \
    && git fetch -q --depth 1 https://github.com/kholia/OSX-KVM.git "${OSX_KVM_REF}" \
    && git checkout -q FETCH_HEAD \
    && git submodule update -q --init --depth 1

WORKDIR /home/arch/OSX-KVM

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

ENV USER=arch

# libguestfs verbose
ENV LIBGUESTFS_DEBUG=1
ENV LIBGUESTFS_TRACE=1

# entrypoint.sh, Launch.sh, enable-ssh.sh, opencore-config.py and the serial
# generator in serial/
COPY --chown=arch:arch --chmod=755 rootfs/home/arch/OSX-KVM/ /home/arch/OSX-KVM/

# OSX-KVM only ships OpenCore.qcow2, so build the NOPICKER=true bootdisk from the
# same config with the picker off. opencore-image-ng.sh takes EFI/ and
# startup.nsh from the current directory.
RUN cp -a ./OpenCore/EFI . \
    && echo 'fs0:\EFI\BOOT\BOOTx64.efi' > startup.nsh \
    && NOPICKER=true ./opencore-config.py > ./nopicker.config.plist \
    && ./serial/opencore-image-ng.sh \
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

# Where GENERATE_UNIQUE writes the generated serials, and GENERATE_SPECIFIC reads them
# from. Mount a file here to reuse the serials in the next container.
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

CMD ["./entrypoint.sh"]
