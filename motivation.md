# OMV ZFS RAID NAS

## Motivation

I plan to migrate from my Synology NAS to a new system with the requirements listed below. I settled on [Openmediavault](https://www.openmediavault.org), but had to find a way to conveniently install it with root on ZFS to fully check all my boxes. I initially [started to write an install script which uses `debootstrap`](https://github.com/Jip-Hop/OMV-ZFS-RAID-NAS/tree/debootstrap) to install Debian. But this soon started feeling messy. Then it dawned on me that [Proxmox](https://pve.proxmox.com) is one of [few](https://www.truenas.com/truenas-scale/) installers which allow installing Linux with root on ZFS with RAID options. I find it a convenient jump-box for installing OMV. And by using the official Proxmox and Openmediavault installer ISOs it now feels like I'm standing on the shoulders of giants when installing using [this method](README.md).

### Requirements

- Open Source
- Fully Encrypted (for both the OS and data)
- Redundancy (for OS and data)
- Versioning (of both the OS and data)
- Admin web interface
- SMB file sharing
- Docker + Portainer support
- Uninterruptible Power Supply (UPS) support (+ web interface)
- Automated backup to cold storage (to e.g. USB, SATA or eSATA)
- Monitoring system health + notifications
- Detect hot-swapped drives

The Fully Encrypted requirement reduced my options by a lot. That's why I developed [sedunlocksrv-pba](https://github.com/Jip-Hop/sedunlocksrv-pba). With this solution based on Self Encrypting Drives (which functions on a layer lower than the operating system) I didn't need to depend on the OS to implement encryption at all.

## Alternatives

- Synology DSM. A very convenient system and it's what I use now. But it's tied to Synology's (usually not very powerful) hardware, not Open Source and lacks proper encryption options.
- TrueNAS SCALE. Had high hopes for this option. It's almost perfect for my needs, except that [it's not supported to just run Docker + Portainer](https://jira.ixsystems.com/browse/NAS-114665). It needs [workarounds](https://www.youtube.com/watch?v=QXooywQSfJY).
- Rockstor. Uses BTRFS and Docker is a first class citizen. But [does not support redundancy for the OS](https://forum.rockstor.com/t/luks-full-disk-encryption-on-rockstor-4-system-drive/7770/7) and lacks support for [monitoring of drives or pools](https://rockstor.com/docs/data_loss.html#rockstor-web-ui-and-data-loss-monitoring).
- [Houston](https://www.45drives.com/solutions/houston/) ([Ubuntu](https://releases.ubuntu.com/20.04/) + [Cockpit](https://cockpit-project.org/) + 45drives plugins). Looks like a viable modular solution. Has [installation instructions for Ubuntu](https://knowledgebase.45drives.com/kb/kb450290-ubuntu-houston-ui-installation/). Especially the [Cockpit ZFS Manager](https://github.com/45Drives/cockpit-zfs-manager) and [Cockpit File Sharing](https://github.com/45Drives/cockpit-file-sharing) plugins look like what I'm after. But it seems like there's no UPS plugin for Cockpit. Apart from that looks like it could match my requirements. I've evaluated Cockpit but haven't actually tested anything from 45drives.
- Proxmox + VM. The additional layer of the hypervisor (Proxmox) provides the ability to snapshot/rollback the main system (inside the VM). Proxmox also checks the redundancy requirement. But because of the additional layer other things become more complicated, such as a clean shutdown when the UPS is low on power, or handling hot-swapped drives. For me the additional complexity of Proxmox for a 'simple' home NAS was not worth it.
- Openmediavault with BTRFS or [LVM + mdadm](https://forum.openmediavault.org/index.php?thread/41263-zfs-on-omv6/&postID=305572#post305572) (or another combination). While BTRFS is already included in the Linux kernel, support for snapshots and management is [not implemented in the Openmediavault web interface](https://github.com/openmediavault/openmediavault/issues/1241). Additionally BTRFS [won't send notifications if a disk dies](https://forum.openmediavault.org/index.php?thread/41263-zfs-on-omv6/&postID=305602#post305602). Lastly, I didn't find a convenient way to rollback or boot into previous snapshots. Although [schnapps](https://gitlab.nic.cz/turris/schnapps) looked interesting. Perhaps LVM + mdadm is still an option, but last time I tried it I found the snapshot functionality very strange...
- [Debootstrap Debian](https://github.com/zbm-dev/zfsbootmenu/wiki/Debian-Bullseye-installation-with-ESP-on-the-zpool-disk) -> [install OMV](https://forum.openmediavault.org/index.php?thread/39490-install-omv6-on-debian-11-bullseye/). The end result could be the same as [this method](README.md). However it would allow more flexibility, for example to setup native ZFS encryption.

Since OMV, TrueNAS SCALE and Houston (can) use ZFS for the data disks, it would be possible to switch between these alternatives quite easily.