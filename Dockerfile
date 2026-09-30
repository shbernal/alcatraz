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

# macserial generates serial numbers for SERIALS=random. OpenCorePkg's release
# binary is static and falls back to a clock-seeded generator without glibc's
# arc4random, so build it against the same glibc as the image.
FROM archlinux:base-devel AS macserial
ARG OPENCORE_VERSION=1.0.8
ARG OPENCORE_SHA256=5f08f0a3af56666d52dba49411ee541f0121ccbe43ff83d477edab38d5073e86
RUN curl -fsSL -o /opencore.tar.gz "https://github.com/acidanthera/OpenCorePkg/archive/refs/tags/${OPENCORE_VERSION}.tar.gz" \
    && sha256sum -c <<< "${OPENCORE_SHA256}  /opencore.tar.gz" \
    && tar -xzf /opencore.tar.gz -C / \
    && make -C "/OpenCorePkg-${OPENCORE_VERSION}/Utilities/macserial" \
    && install -Dm755 "/OpenCorePkg-${OPENCORE_VERSION}/Utilities/macserial/macserial" /usr/local/bin/macserial

FROM archlinux:base

# archlinux:base is a rolling tag. Pass the digest it resolved to, so a
# broken rebuild can be traced to its base.
ARG BASE_DIGEST
LABEL org.opencontainers.image.base.name=docker.io/library/archlinux:base
LABEL org.opencontainers.image.base.digest=${BASE_DIGEST}
LABEL org.opencontainers.image.title=alcatraz
LABEL org.opencontainers.image.description="macOS in a container: QEMU/KVM with OSX-KVM's OpenCore"
LABEL org.opencontainers.image.source=https://github.com/shbernal/alcatraz
LABEL org.opencontainers.image.licenses=GPL-3.0-or-later
LABEL org.opencontainers.image.url=https://github.com/shbernal/alcatraz
LABEL org.opencontainers.image.documentation=https://github.com/shbernal/alcatraz#readme
LABEL org.opencontainers.image.authors=shbernal
# Blank the labels inherited from archlinux:base; the release build sets them.
LABEL org.opencontainers.image.version="" org.opencontainers.image.revision="" org.opencontainers.image.created=""

# mtools builds the bootdisks.
RUN pacman -Syu --noconfirm qemu-desktop edk2-ovmf mtools python openssh \
    && yes | pacman -Scc \
    && useradd -m -u 1000 alcatraz

# The container's own sshd, for SSH=true.
RUN mkdir -p -m 700 /root/.ssh \
    && touch /root/.ssh/authorized_keys \
    && chmod 644 /root/.ssh/authorized_keys \
    && printf '%s\n' 'AllowTcpForwarding yes' 'PermitTunnel yes' 'X11Forwarding yes' \
        'PasswordAuthentication yes' 'PermitRootLogin yes' 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config

# OSX-KVM provides the firmware, the OpenCore bootdisk and its config, and the
# macOS download script. It stays as fetched. Bump the commit on purpose and
# test a boot.
ARG OSX_KVM_REF=4c378a4b5e0b219783683012bec680325eb40719
ADD https://github.com/kholia/OSX-KVM.git#${OSX_KVM_REF} /opt/osx-kvm

COPY --chmod=755 rootfs/opt/alcatraz/ /opt/alcatraz/
COPY --from=macserial /usr/local/bin/macserial /usr/local/bin/macserial

# The default bootdisks, with and without the picker. OSX-KVM's own
# OpenCore.qcow2 leaves the resolution to OVMF, which boots at 1280x800.
RUN /opt/alcatraz/build-bootdisk.sh /opt/alcatraz/picker.qcow2 \
    && BOOT_PICKER=false /opt/alcatraz/build-bootdisk.sh /opt/alcatraz/nopicker.qcow2

# Everything a container writes lives in /data: see README.md.
RUN install -d -o alcatraz -g alcatraz /data

WORKDIR /data

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
ENV APPLEID_PATCH=false
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
