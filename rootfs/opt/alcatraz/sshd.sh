#!/bin/bash
# alcatraz: macOS in a container
# https://github.com/shbernal/alcatraz
# Hard fork of Docker-OSX by Sick.Codes (https://github.com/sickcodes/Docker-OSX)
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Starts the container's own sshd in the background (SSH=true), generating the
# host keys on first use.
# docker exec … /opt/alcatraz/sshd.sh
if [[ ! -f /etc/ssh/ssh_host_rsa_key && ! -f /etc/ssh/ssh_host_ecdsa_key && ! -f /etc/ssh/ssh_host_ed25519_key ]]; then
    /usr/bin/ssh-keygen -A
fi
nohup /usr/bin/sshd -D &
