# overlay_root.sh
Read-only root-fs for linux systems. This bash scrips allow for the root fs to be mounted as read only, all writes are make to a tmpfs in place of the disk.

This script has been forked from: https://wiki.psuter.ch/doku.php?id=solve_raspbian_sd_card_corruption_issues_with_read-only_mounted_root_partition


# Installation
1. Download the script and install to `/usr/sbin/overlay_root.sh` or some other location.
2. Ensure that the script is executable `chmod +x /usr/sbin/overlay_root.sh`
3. Add to the kernel args `init=/sbin/overlay_root.sh`.

### System Requirements
* Linux kernel version 3.18 and newer
* pivot_root
* overlay
