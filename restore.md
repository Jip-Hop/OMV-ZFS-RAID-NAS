# OMV ZFS RAID NAS

## Snapshot Restore

To restore the operating system from a snapshot, reboot into ZFSBootMenu. Press `Escape` during the countdown timer to enter ZFSBootMenu. In the menu make sure `rpool/omv/` is selected and press `CTRL+S` to list the snapshots. Select the snapshot you want to boot into and press `Enter`. Confirm the name (or change it) and press `Enter`. A new dataset will be created based on this snapshot. Press `Escape` to go back to the main menu. At this point you may select the newly created dataset and press `Enter` to boot your system to the previous state.

> NOTE: Docker (and thus also Portainer) are 'isolated' from the OMV base installation by means of a dedicated Docker ZFS dataset. Rolling back OMV will leave all Docker containers, images and volumes intact on the Docker dataset. This means that restoring from a snapshot will not necessarily be consistent with how the system was when taking the snapshot (OMV is restored to a previous date, but all Docker related data is still current).

If the system is working well in this state, and you wish to boot it by default, set the default boot environment. For example `zpool set bootfs=rpool/omv_NEW rpool`. You can then remove the old dataset (but trying to do so from the Web GUI will result in [an error](https://github.com/Jip-Hop/OMV-ZFS-RAID-NAS/issues/2)). So for now use the terminal for this. Don't forget to remove children datasets (snapshots) of the old dataset too:

```
root@nas:~# zfs destroy rpool/omv
cannot destroy 'rpool/omv': filesystem has children
use '-r' to destroy the following datasets:
rpool/omv@install
```