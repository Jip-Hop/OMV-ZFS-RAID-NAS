#!/bin/bash
#
# Install Debian GNU/Linux 11 Bullseye + Openmediavault to a native ZFS root filesystem.
# Run this script when booting into an Ubuntu Desktop Live CD (supports ZFS out of the box).
# Tested to work with: ubuntu-20.04.4-desktop-amd64.iso.
#
# Credits:
# https://github.com/Jip-Hop/
# https://github.com/hn/debian-buster-zfs-root
# https://github.com/kewiha/debian-bullseye-zfs-root
# https://github.com/Sithuk/ubuntu-server-zfsbootmenu/
# https://github.com/zbm-dev/zfsbootmenu/wiki/Debian-Bullseye-installation-with-ESP-on-the-zpool-disk
# https://openzfs.github.io/openzfs-docs/Getting%20Started/Debian/Debian%20Bullseye%20Root%20on%20ZFS.html
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3.0 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.txt>.

set -euxo pipefail

### Static settings

ZPOOL=zroot
TARGETDIST=bullseye # Should be a version supported by OMV 
KERNELVERSION="5.15" # Proxmox kernel version
PASSWORD="root" # Password in new install
LOCALE="en_US.UTF-8" # New install language setting
TIMEZONE="Europe/Amsterdam" # New install timezone setting

PARTEFI=1
PARTZFS=2

NEWHOST="omv" # Hostname of new install
EFIBINARY="https://github.com/zbm-dev/zfsbootmenu/releases/download/v1.12.0/zfsbootmenu-release-vmlinuz-x86_64-v1.12.0.EFI"
POSTINSTALLSCRIPT="https://github.com/Jip-Hop/OMV-ZFS-RAID-NAS/blob/debootstrap/postinstall.sh"

# Check for root priviliges
if [ "$(id -u)" -ne 0 ]; then
   echo "Please run as root."
   exit 1
fi

### User settings

declare -A BYID
while read -r IDLINK; do
	BYID["$(basename "$(readlink "$IDLINK")")"]="$IDLINK"
done < <(find /dev/disk/by-id/ -type l)

for DISK in $(lsblk -I8,254,259 -dn -o name); do
	if [ -z "${BYID[$DISK]}" ]; then
		SELECT+=("$DISK" "(no /dev/disk/by-id persistent device name available)" off)
	else
		SELECT+=("$DISK" "${BYID[$DISK]}" off)
	fi
done

TMPFILE=$(mktemp)
whiptail --backtitle "$0" --title "Drive selection" --separate-output \
	--checklist "\nPlease select ZFS drives\n" 20 74 8 "${SELECT[@]}" 2>"$TMPFILE"

if [ $? -ne 0 ]; then
	exit 1
fi

while read -r DISK; do
	if [ -z "${BYID[$DISK]}" ]; then
		DISKS+=("/dev/$DISK")
		ZFSPARTITIONS+=("/dev/$DISK$PARTZFS")
	else
		DISKS+=("${BYID[$DISK]}")
		ZFSPARTITIONS+=("${BYID[$DISK]}-part$PARTZFS")
	fi
done < "$TMPFILE"

whiptail --backtitle "$0" --title "RAID level selection" --separate-output \
	--radiolist "\nPlease select ZFS RAID level\n" 20 74 8 \
	"RAID0" "Striped disks or single disk" off \
	"RAID1" "Mirrored disks (RAID10 for n>=4)" on \
	"RAIDZ" "Distributed parity, one parity block" off \
	"RAIDZ2" "Distributed parity, two parity blocks" off \
	"RAIDZ3" "Distributed parity, three parity blocks" off 2>"$TMPFILE"

if [ $? -ne 0 ]; then
	exit 1
fi

RAIDLEVEL=$(head -n1 "$TMPFILE" | tr '[:upper:]' '[:lower:]')

case "$RAIDLEVEL" in
  raid0)
	RAIDDEF="${ZFSPARTITIONS[*]}"
  	;;
  raid1)
	if [ $((${#ZFSPARTITIONS[@]} % 2)) -ne 0 ]; then
		echo "Need an even number of disks for RAID level '$RAIDLEVEL': ${ZFSPARTITIONS[@]}" >&2
		exit 1
	fi
	I=0
	for ZFSPARTITION in "${ZFSPARTITIONS[@]}"; do
		if [ $((I % 2)) -eq 0 ]; then
			RAIDDEF+=" mirror"
		fi
		RAIDDEF+=" $ZFSPARTITION"
		((I++)) || true
	done
  	;;
  *)
	if [ ${#ZFSPARTITIONS[@]} -lt 3 ]; then
		echo "Need at least 3 disks for RAID level '$RAIDLEVEL': ${ZFSPARTITIONS[@]}" >&2
		exit 1
	fi
	RAIDDEF="$RAIDLEVEL ${ZFSPARTITIONS[*]}"
  	;;
esac

whiptail --backtitle "$0" --title "Confirmation" \
	--yesno "\nAre you sure to destroy ZFS pool '$ZPOOL' (if existing), wipe all data of disks '${DISKS[*]}' and create a RAID '$RAIDLEVEL'?\n" 20 74

if [ $? -ne 0 ]; then
	exit 1
fi

### Start the real work

# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=595790
if [ "$(hostid | cut -b-6)" == "007f01" ]; then
	dd if=/dev/urandom of=/etc/hostid bs=1 count=4
fi

apt update
# Install dependencies
DEBIAN_FRONTEND=noninteractive apt install --yes debootstrap curl ca-certificates gnupg gdisk parted dosfstools

zfs umount -a
# TODO: export all ZFS datasets, just in case this script is called again

test -d /proc/spl/kstat/zfs/$ZPOOL && zpool destroy $ZPOOL

# Download EFI binary
curl -fsSL $EFIBINARY -o /tmp/bootx64.efi
mkdir -pv /tmp/boot/efi

I=0

# Create partition table
for DISK in "${DISKS[@]}"; do
	echo -e "\nPartitioning disk $DISK"

	wipefs -a $DISK
	sgdisk --zap-all $DISK

	sgdisk -a1 -n$PARTEFI:1m:+512m -t$PARTEFI:ef00 \
            		-n$PARTZFS:0:0        -t$PARTZFS:bf00 $DISK

	partprobe $DISK
	sleep 2

	EFIPARTITION="$DISK-part$PARTEFI"
	mkfs -t vfat -F 32 -s 1 -n EFI-$I $EFIPARTITION
	mount $EFIPARTITION /tmp/boot/efi
	mkdir -pv /tmp/boot/efi/EFI/boot/

	# Copy EFI binary to all disks, to prevent it being a single point of failure
	cp -v /tmp/bootx64.efi /tmp/boot/efi/EFI/boot/bootx64.efi
	umount $EFIPARTITION

	# Don't mount EFI via fstab, there's no need for it to be mounted once the system has booted
	# Mounting the EFI could fail if the disk is missing (degraded RAID)
	((I++)) || true
done

sleep 2

# Create a ZFS pool
zpool create -f -o ashift=12 -o autotrim=on -O acltype=posixacl -O compression=lz4 -O normalization=formD -O atime=off -O xattr=sa -O mountpoint=none -R /mnt $ZPOOL $RAIDDEF
if [ $? -ne 0 ]; then
	echo "Unable to create zpool '$ZPOOL'" >&2
	exit 1
fi

# Create filesystems to hold the Debian boot environment
zfs create $ZPOOL/ROOT
zfs create -o canmount=noauto -o mountpoint=/ $ZPOOL/ROOT/debian
zfs mount $ZPOOL/ROOT/debian

# Set the default boot environment to tell ZFSBootMenu what it should prefer to boot
zpool set bootfs=$ZPOOL/ROOT/debian $ZPOOL

# Re-import the pool with a temporary root to populate the filesystems
zpool export $ZPOOL
zpool import -N -R /mnt $ZPOOL
zfs mount $ZPOOL/ROOT/debian
zfs mount -a

# Download signature, used by debootstrap
curl -fsSLO https://ftp-master.debian.org/keys/archive-key-11.asc
curl -fsSLO https://ftp-master.debian.org/keys/archive-key-11-security.asc

# Manually create a keyring file and add downloaded keys
mkdir -p /usr/share/keyrings/
gpg --no-default-keyring --keyring=/usr/share/keyrings/debian-archive-keyring.gpg --import archive-key-11.asc
gpg --no-default-keyring --keyring=/usr/share/keyrings/debian-archive-keyring.gpg --import archive-key-11-security.asc

# Bind virtual filesystems from the live environment into the target hierarchy
for i in dev sys proc run; do mount --rbind /$i /mnt/$i && mount --make-rslave /mnt/$i; done

# Install the Debian base
debootstrap --include wget,curl,ca-certificates,apt-transport-https,locales,console-setup,lsb-release --arch amd64 ${TARGETDIST} /mnt https://deb.debian.org/debian

# Set a hostname and add it to the hosts file
echo "$NEWHOST" > /mnt/etc/hostname
echo -e "127.0.1.1\t$NEWHOST" >> /mnt/etc/hosts

# Copy hostid as the target system will otherwise not be able to mount the misleadingly foreign file system
cp -va /etc/hostid /mnt/etc/

# Download postinstall script
curl $POSTINSTALLSCRIPT -o /mnt/root/postinstall.sh
chmod +x /mnt/root/postinstall.sh

# Setup DHCP networking
ETHDEV=$(udevadm info -e | grep "ID_NET_NAME_ONBOARD=" | head -n1 | cut -d= -f2) || true # Selects 1st onboard NIC, if present
if [ "$ETHDEV" == "" ] ; then
	ETHDEV=$(udevadm info -e | grep "ID_NET_NAME_PATH=" | head -n1 | cut -d= -f2) || true # Selects 1st addin NIC, if present
fi
test -n "$ETHDEV" || ETHDEV=enp0s1
echo -e "\nauto $ETHDEV\niface $ETHDEV inet dhcp\n" >> /mnt/etc/network/interfaces

# Setup package repository sources
echo "deb https://deb.debian.org/debian ${TARGETDIST} main contrib" > /mnt/etc/apt/sources.list	
echo "deb https://deb.debian.org/debian-security/ ${TARGETDIST}-security main contrib" >> /mnt/etc/apt/sources.list
echo "deb https://deb.debian.org/debian ${TARGETDIST}-updates main contrib" >> /mnt/etc/apt/sources.list

curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-${TARGETDIST}.gpg -o /mnt/etc/apt/trusted.gpg.d/proxmox-release-${TARGETDIST}.gpg
# Proxmox repo doesn't do https... but contents are at least validated with a key
echo "deb [arch=amd64] http://download.proxmox.com/debian/pve ${TARGETDIST} pve-no-subscription" > /mnt/etc/apt/sources.list.d/pve-install-repo.list

# NOTE: don't manually add Docker repo, will conflict with omv-extras

# # Add Docker’s official GPG key and stable repository
# curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /mnt/usr/share/keyrings/docker-archive-keyring.gpg
# echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian ${TARGETDIST} stable" > /mnt/etc/apt/sources.list.d/docker.list

# Run script in chroot
chroot /mnt /bin/bash -x <<-EOCHROOT
	set -euxo pipefail
	export DEBIAN_FRONTEND=noninteractive

	# Set default password for root user
	echo -e "root:$PASSWORD" | chpasswd

	# TODO: Make perl happy (keeps complaining about locales)
	export LANGUAGE=en_US.UTF-8
	export LC_ALL=en_US.UTF-8
	export LANG=en_US.UTF-8
	export LC_CTYPE=en_US.UTF-8

	locale-gen en_US.UTF-8 $LOCALE
	# echo 'LANG="$LOCALE"' > /etc/default/locale

	dpkg-reconfigure -f noninteractive locales

	# locale-gen en_US.UTF-8 $LOCALE
	# echo 'LANG="$LOCALE"' > /etc/default/locale

	# Set timezone
	ln -fs /usr/share/zoneinfo/"$TIMEZONE" /etc/localtime
	dpkg-reconfigure -f noninteractive tzdata

	apt update && apt full-upgrade -y

	# Install kernel with zfs support (need to use no-install-recommends otherwise installs grub)
	apt install -y --no-install-recommends --fix-missing pve-kernel-${KERNELVERSION} pve-headers-${KERNELVERSION}
	# TODO: Check need to install pve-headers (without version)
	
	# Install zfs and docker
	apt install -y zfsutils-linux zfs-zed zfs-initramfs
	# apt install -y docker-ce docker-ce-cli containerd.io

	# TODO: fix error "The ZFS modules are not loaded"

	# TODO: limit ZFS ram usage

	# TODO: do I need to call update-initramfs? Or is this already done by apt install pve-kernel??
	# Generate an initramfs image
	# update-initramfs -c -k all
	
	# Enable systemd zfs services
	systemctl enable zfs.target
	systemctl enable zfs-import-cache
	systemctl enable zfs-mount
	systemctl enable zfs-import.target
EOCHROOT

# Set cachefile property for the pool
# zpool set cachefile=/mnt/etc/zfs/zpool.cache $ZPOOL

# Setup requiring user interaction
chroot /mnt dpkg-reconfigure keyboard-configuration console-setup

sync

cd
sleep 2
umount -R /mnt
zpool export -a

echo -e "Done installing base system!\n- Please manually reboot\n- Login with username \"root\" and password \"$PASSWORD\"\n- Then run postinstall.sh"