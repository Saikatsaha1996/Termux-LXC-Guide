#!/usr/bin/env sh

# Ensure cgroup2 is mounted properly

CGROUP_ROOT="/sys/fs/cgroup"

# Remount RW temporarily
mount -o remount,rw ${CGROUP_ROOT} 2>/dev/null

# If already cgroup2 → skip
if mount | grep -q "type cgroup2"; then
    echo "[+] cgroup v2 already mounted"
else
    echo "[*] Mounting cgroup v2..."

    # Cleanup old v1 mounts (safe minimal cleanup)
    for cg in cpu cpuacct schedtune cpu,cpuacct; do
        umount -l "${CGROUP_ROOT}/${cg}" 2>/dev/null
        rm -rf "${CGROUP_ROOT:?}/${cg}"
    done

    # Mount unified cgroup v2
    mount -t cgroup2 none ${CGROUP_ROOT} || {
        echo "[-] Failed to mount cgroup2"
        exit 1
    }
fi

# Remount RO back (optional)
mount -o remount,ro ${CGROUP_ROOT} 2>/dev/null

echo "[+] cgroup v2 ready"

exit 0
