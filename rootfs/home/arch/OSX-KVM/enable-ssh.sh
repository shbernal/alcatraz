#!/bin/bash
# Starts sshd in the background, generating the host keys on first use.
# docker exec … ./enable-ssh.sh
if [[ ! -f /etc/ssh/ssh_host_rsa_key && ! -f /etc/ssh/ssh_host_ecdsa_key && ! -f /etc/ssh/ssh_host_ed25519_key ]]; then
    sudo /usr/bin/ssh-keygen -A
fi
nohup sudo /usr/bin/sshd -D &
