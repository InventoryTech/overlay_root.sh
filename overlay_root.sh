#!/bin/sh
#  Read-only Root-FS using overlayfs
#  Version 2.0
#
#  Version History:
#  1.0: initial release
#  1.1: adopted new fstab style with PARTUUID. the script will now look for a /dev/xyz definiton first 
#       (old raspbian), if that is not found, it will look for a partition with LABEL=rootfs, if that
#       is not found it look for a PARTUUID string in fstab for / and convert that to a device name
#       using the blkid command.
#  1.2: renamed bash script
#  2.0: adapted to use a persistent partition rather then a tmpfs
#
#  Created 2017 by Pascal Suter @ DALCO AG, Switzerland to work on Raspian as custom init script
#  (raspbian does not use an initramfs on boot)
#  Update 1.2 & 2.0 by InventoryTech@github 2023
#  
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see
#    <http://www.gnu.org/licenses/>.
#
#
#  This script will mount the root filesystem read-only and overlay it with a separate ext4 partition 
#  which is read-write mounted. This is done using the overlayFS which is part of the linux kernel 
#  since version 3.18. 
#  when this script is in use, all changes made to anywhere in the root filesystem mount will made to a separate partition.
#  The root filesystem will only be accessed as read-only drive, this prevents changes to the root filesystem over time and
#  helps to prevent filesystem coruption and improves system updates. 
#
#  Install: 
#  copy this script to /usr/sbin/overlay_root.sh, make it executable and add "init=/usr/sbin/overlay_root.sh" to the kernel arguments
#  To makes chnages to the root filesystem it can be remounted as read-write like so "sudo mount -o remount,rw /dev/mmcblk0p2 /ro"
#  once all changes have been made remount as read-only "sudo mount -o remount,ro /dev/mmcblk0p2 /ro"
 
fail(){
	echo -e "$1"
	/bin/bash
}

PERSISTENT_PARTITION=/dev/mmcblk0p5
PERSISTENT_PARTITION_TYPE=ext4
 
# load module
modprobe overlay
if [ $? -ne 0 ]; then
    fail "ERROR: missing overlay kernel module"
fi

# mount /proc
mount -t proc proc /proc
if [ $? -ne 0 ]; then
    fail "ERROR: could not mount proc"
fi

# create a writable fs to then create our mountpoints 
mount -t tmpfs inittemp /mnt
if [ $? -ne 0 ]; then
    fail "ERROR: could not create a temporary filesystem to mount the base filesystems for overlayfs"
fi
mkdir /mnt/overlay    # upper and work
mkdir /mnt/oldroot    # lower
mkdir /mnt/newroot    # overlayfs

mount -t ${PERSISTENT_PARTITION_TYPE} ${PERSISTENT_PARTITION} /mnt/overlay
if [ $? -ne 0 ]; then
    fail "ERROR: could not mount persistent filesystem for overlay"
fi

mkdir -p /mnt/overlay/upper
mkdir -p /mnt/overlay/work

# mount root filesystem readonly 
rootDev=`cat /proc/cmdline | sed -e 's/^.*root=//' -e 's/ .*$//'`   # get rootfs from kernel args
rootMountOpt=`awk '$2 == "/" {print $4}' /etc/fstab`                # get mount options from fstab
rootFsType=`awk '$2 == "/" {print $3}' /etc/fstab`                  # get fs type from fstab

blkid $rootDev
if [ $? -gt 0 ]; then
    fail "ERROR: could not find a root filesystem device from Kernel args!"
fi

# mount the rootfs as lower read only
mount -t ${rootFsType} -o ${rootMountOpt},ro ${rootDev} /mnt/oldroot
if [ $? -ne 0 ]; then
    fail "ERROR: could not ro-mount original root partition"
fi

mount -t overlay -o lowerdir=/mnt/oldroot,upperdir=/mnt/overlay/upper,workdir=/mnt/overlay/work overlayfs-root /mnt/newroot
if [ $? -ne 0 ]; then
    fail "ERROR: could not mount overlayFS"
fi

# create mountpoints inside the new root filesystem-overlay
mkdir -p /mnt/newroot/ro
mkdir -p /mnt/newroot/rw

# remove root mount from fstab (this is already a non-permanent modification)
grep -v "$rootDev" /mnt/oldroot/etc/fstab > /mnt/newroot/etc/fstab
echo "# the original root mount has been removed by overlay_root.sh" >> /mnt/newroot/etc/fstab
echo "# this is only a temporary modification, the original fstab" >> /mnt/newroot/etc/fstab
echo "# stored on the disk can be found in /ro/etc/fstab" >> /mnt/newroot/etc/fstab

# change to the new overlay root
cd /mnt/newroot
pivot_root . mnt
exec chroot . sh -c "$(cat <<END
# move ro and rw mounts to the new root
mount --move /mnt/mnt/oldroot/ /ro
if [ $? -ne 0 ]; then
    echo "ERROR: could not move ro-root into newroot"
    /bin/bash
fi
mount --move /mnt/mnt/overlay /rw
if [ $? -ne 0 ]; then
    echo "ERROR: could not move tempfs rw mount into newroot"
    /bin/bash
fi
# unmount unneeded mounts so we can unmout the old readonly root
umount /mnt/mnt
umount /mnt/proc
umount /mnt/dev
umount /mnt
# continue with regular init
exec /sbin/init
END
)"