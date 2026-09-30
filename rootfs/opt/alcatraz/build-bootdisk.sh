#!/bin/bash
# alcatraz: macOS in a container
# https://github.com/shbernal/alcatraz
# SPDX-License-Identifier: GPL-3.0-or-later
#
# build-bootdisk.sh <output.qcow2>
# Builds an OpenCore bootdisk from OSX-KVM's EFI and opencore-config.py's
# config, which takes the serials, resolution and BOOT_PICKER from the environment.
# The disk is GPT with a single FAT EFI system partition, written with mtools,
# so it needs neither root nor loop devices.
set -euo pipefail
output="$(realpath -m "$1")"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
esp="${work}/esp"
mkdir -p "${esp}"
cp -a /opt/osx-kvm/OpenCore/EFI "${esp}/"
rm -rf "${esp}/EFI/OC/Resources"
cp -a /opt/osx-kvm/resources/OcBinaryData/Resources "${esp}/EFI/OC/"
/opt/alcatraz/opencore-config.py > "${esp}/EFI/OC/config.plist"
echo 'fs0:\EFI\BOOT\BOOTx64.efi' > "${esp}/startup.nsh"

# 1 MiB of alignment, a 254 MiB ESP, and room for the backup GPT.
raw="${work}/bootdisk.raw"
truncate -s 256M "${raw}"
sfdisk -q "${raw}" <<< 'label: gpt
start=1MiB, size=254MiB, type=uefi, name="EFI"'
export MTOOLS_SKIP_CHECK=1
mformat -i "${raw}@@1M" -T $((254 * 2048)) -h 64 -s 32 -v EFI ::
mcopy -s -Q -i "${raw}@@1M" "${esp}"/* ::/

qemu-img convert -O qcow2 "${raw}" "${output}"
