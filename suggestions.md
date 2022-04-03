# OMV ZFS RAID NAS

## Suggestions

Now that you have your fancy OMV NAS with a ZFS root filesystem. What to do next? Or how to install things a bit differently? Here are some suggestions:

- Setup email notifications (also enable ZFS ZED notifications) in the OMV Web GUI.
- Setup cron job to [manually run `zpool trim`](https://askubuntu.com/a/1200415).
- Automatically create snapshots (e.g. with [pyznap](https://github.com/yboetz/pyznap)).
- Make a data-only zpool (add more disks first) to store all your userdata and Shared Folders.
- Install the openmediavault-sharerootfs plugin and make a ZFS dataset just for user data (will persist when restoring OS snapshots). Then there's no need to add more disks.
- Leave some unpartitioned space when installing Proxmox. You can use the remaining space to make a mdadm array for swap. Or even an ext4 filesystem to use for `/var/lib/docker` if you don't want Docker to use the ZFS storage driver because [it will create many datasets](https://github.com/moby/moby/issues/41055). In that case I recommend to use the ext4 filesystem only for Docker images and put all of the persistent container data on a ZFS dataset (by using bind mounts instead of volumes) so you can keep snapshots of your data. Using an ext4 formatted zvol instead of using the remaining unpartitioned space is an option too, but that may lead to heavy [write amplification](https://www.reddit.com/r/zfs/comments/tfvrhj/optimizing_zvols_for_ext4_use/).
- Build ZFSBootMenu using Docker (with SSH access enabled) instead of downloading prebuilt release.
- There are [alternative methods to provide redundancy for ZFSBootMenu](https://github.com/zbm-dev/zfsbootmenu/discussions/276#discussioncomment-2338924). For example you could make an mdraid array from the EFI system partitions.
- You could probably choose different ZFS RAID options (or no RAID) when installing Proxmox and still follow the rest of the steps.
- Instead of using the Openmediavault ISO, you could try installing a clean Debian Bullseye server using the same process. Use the steps provided as inspiration.
- Tweak [ZFS RAM usage](https://pbs.proxmox.com/docs/sysadmin.html#limit-zfs-memory-usage).