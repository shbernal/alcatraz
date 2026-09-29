# alcatraz: macOS in a container
# https://github.com/shbernal/alcatraz
# Hard fork of Docker-OSX by Sick.Codes (https://github.com/sickcodes/Docker-OSX)
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Built on OSX-KVM by Dhiru Kholia (https://github.com/kholia/OSX-KVM), with
# OpenCore support from https://github.com/Leoyzen/KVM-Opencore and
# https://github.com/thenickdude/KVM-Opencore/
#
# Build:
#
#       docker build -t alcatraz .
#
# Run (settings and recipes in README.md and FAQ.md):
#
#       docker run -it --device /dev/kvm -p 50922:10022 -v ./mac:/data \
#           -v /tmp/.X11-unix:/tmp/.X11-unix -e "DISPLAY=${DISPLAY:-:0.0}" \
#           ghcr.io/shbernal/alcatraz:latest

FROM archlinux:base-devel

# archlinux:base-devel is a rolling tag. Pass the digest it resolved to, so a
# broken rebuild can be traced to its base.
ARG BASE_DIGEST
LABEL org.opencontainers.image.base.name=docker.io/library/archlinux:base-devel
LABEL org.opencontainers.image.base.digest=${BASE_DIGEST}
LABEL org.opencontainers.image.title=alcatraz
LABEL org.opencontainers.image.description="macOS in a container: QEMU/KVM with OSX-KVM's OpenCore"
LABEL org.opencontainers.image.source=https://github.com/shbernal/alcatraz
LABEL org.opencontainers.image.licenses=GPL-3.0-or-later
LABEL org.opencontainers.image.url=https://github.com/shbernal/alcatraz
LABEL org.opencontainers.image.documentation=https://github.com/shbernal/alcatraz#readme
LABEL org.opencontainers.image.authors=shbernal
# Blank the labels inherited from archlinux:base-devel; the release build sets them.
LABEL org.opencontainers.image.version="" org.opencontainers.image.revision="" org.opencontainers.image.created=""

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

RUN pacman -Syu git alsa-utils openssh --noconfirm \
    && useradd -m alcatraz \
    && tee -a /etc/sudoers <<< 'alcatraz ALL=(ALL) NOPASSWD: ALL'

# allow ssh to container
RUN mkdir -p -m 700 /root/.ssh \
    && touch /root/.ssh/authorized_keys \
    && chmod 644 /root/.ssh/authorized_keys

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

RUN pacman -Syu bc qemu-desktop edk2-ovmf wget --overwrite '*' --noconfirm \
    && yes | pacman -Scc

# libguestfs builds the bootdisks (nopicker at build time, serials at run time).
# Its appliance needs a kernel, which is most of this layer's size.
RUN pacman -Syu linux linux-headers archlinux-keyring guestfs-tools mkinitcpio --noconfirm \
    && libguestfs-test-tool \
    && rm -rf /var/tmp/.guestfs-* \
    && yes | pacman -Scc

# OSX-KVM provides the firmware, the OpenCore bootdisk and its config, and the
# macOS download script. It stays as fetched. Bump the commit on purpose and
# test a boot.
ARG OSX_KVM_REF=4c378a4b5e0b219783683012bec680325eb40719
RUN git init -q /opt/osx-kvm \
    && cd /opt/osx-kvm \
    && git fetch -q --depth 1 https://github.com/kholia/OSX-KVM.git "${OSX_KVM_REF}" \
    && git checkout -q FETCH_HEAD \
    && git submodule update -q --init --depth 1

COPY --chmod=755 rootfs/opt/alcatraz/ /opt/alcatraz/

# OSX-KVM only ships OpenCore.qcow2 (with the picker), so build the picker-less
# bootdisk from the same config.
RUN BOOT_PICKER=false /opt/alcatraz/build-bootdisk.sh /opt/alcatraz/nopicker.qcow2 \
    && rm -rf /var/tmp/.guestfs-*

# Everything a container writes lives in /data: see README.md.
RUN install -d -o alcatraz -g alcatraz /data

USER alcatraz
WORKDIR /data
ENV USER=alcatraz

# Runtime settings, documented in README.md.
ENV MACOS_VERSION=tahoe
ENV RAM=4
ENV CPUS=4
ENV CORES=4
ENV CPU_MODEL=Skylake-Client,-hle,-rtm
ENV CPU_FLAGS=kvm=on,vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on,+ssse3,+sse4.2,+popcnt,+avx,+aes,+xsave,+xsaveopt,check
ENV ACCEL=kvm:tcg
ENV DISK_PATH=/data/disk.img
ENV DISK_FORMAT=qcow2
ENV DISK_SIZE=256G
ENV INSTALLER_PATH=/data/installer.img
ENV INSTALLER_FORMAT=qcow2
ENV BOOT_PICKER=true
ENV BOOTDISK=
ENV SERIALS=default
ENV WIDTH=1920
ENV HEIGHT=1080
ENV NETWORKING=virtio-net-pci
ENV MAC_ADDRESS=52:54:00:09:49:17
ENV INTERNAL_SSH_PORT=10022
ENV SCREEN_SHARE_PORT=5900
ENV PORTS=
ENV AUDIO_DRIVER=alsa
ENV DISPLAY=:0.0
ENV QEMU_ARGS=
ENV SSH=false

VOLUME ["/data"]

CMD ["/opt/alcatraz/entrypoint.sh"]
