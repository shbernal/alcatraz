#!/bin/bash
# alcatraz: macOS in a container
# https://github.com/shbernal/alcatraz
# SPDX-License-Identifier: GPL-3.0-or-later
#
# build-bootdisk.sh <output.qcow2>
# Builds an OpenCore bootdisk from OSX-KVM's EFI and opencore-config.py's
# config, which takes the serials, resolution and BOOT_PICKER from the environment.
set -euo pipefail
output="$(realpath -m "$1")"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
cp -a /opt/osx-kvm/OpenCore/EFI "${work}/"
ln -s /opt/osx-kvm/resources "${work}/resources"
echo 'fs0:\EFI\BOOT\BOOTx64.efi' > "${work}/startup.nsh"
/opt/alcatraz/opencore-config.py > "${work}/config.plist"

cd "${work}"
/opt/alcatraz/vendor/osx-serial-generator/opencore-image-ng.sh --cfg ./config.plist --img "${output}"
