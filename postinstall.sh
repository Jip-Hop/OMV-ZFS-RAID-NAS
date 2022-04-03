#!/bin/bash

OMVINSTALLER="https://github.com/Jip-Hop/installScript/raw/master/install"

curl -fsSL $OMVINSTALLER -o install
chmod +x install
./install -n # don't setup networking
rm install

# TODO: openmediavault trashes my network config from /mnt/etc/network/interfaces
# how to enable dhcp and dns like it was before? Or is this only an issue in my VM?

DEBIAN_FRONTEND=noninteractive apt install -y openmediavault-flashmemory 
# NOTE: reboot to make openmediavault-flashmemory work
DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends openmediavault-zfs # Don't install recommended packages

# TODO: ensure /var/lib/docker is not on ZFS storage?
omv-installdocker

# TODO: Ask user to change root password.
# NOTE: don't install openmediavault-kernel plugin. Proxmox kernel is already installed but doesn't show up in this menu...