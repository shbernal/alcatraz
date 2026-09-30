#!/bin/bash
# alcatraz: macOS in a container
# https://github.com/shbernal/alcatraz
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: generate-serials.sh OUTPUT [MODEL]
#
# Writes a random machine identity as a sourceable env file: serial and board
# serial from macserial, a random UUID, and a MAC address under an Apple prefix.
set -euo pipefail

output="${1:?usage: generate-serials.sh OUTPUT [MODEL]}"
model="${2:-iMacPro1,1}"

IFS=' |' read -r serial board_serial < <(macserial --num 1 --model "${model}")

uuid="$(uuidgen)"

apple_ouis=(00:1B:63 00:1E:C2 00:25:00 3C:07:54 68:5B:35 7C:D1:C3 A8:5C:2C AC:BC:32 D0:81:7A F0:18:98)
read -r b1 b2 b3 < <(od -An -N3 -tx1 /dev/urandom)
mac="${apple_ouis[RANDOM % ${#apple_ouis[@]}]}:${b1}:${b2}:${b3}"

cat > "${output}" <<EOF
export DEVICE_MODEL="${model}"
export SERIAL="${serial}"
export BOARD_SERIAL="${board_serial}"
export UUID="${uuid^^}"
export MAC_ADDRESS="${mac^^}"
EOF
