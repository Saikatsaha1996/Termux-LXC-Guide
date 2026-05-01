#!/usr/bin/env sh

# Post-stop script for LXC containers

# If container stopped then umount the bind mounted rootfs and restore it's nosuid if it was set
umount -Rl "${LXC_ROOTFS_PATH}" 2>/dev/null
umount -l "${LXC_ROOTFS_PATH}" 2>/dev/null

exit 0
