#!/usr/bin/env sh

# Pure Cgroup v2 initialization
CGROUP_ROOT="/sys/fs/cgroup"

# ১. যদি অলরেডি cgroup2 মাউন্ট করা থাকে, তবে আর কিছু করার নেই
if mount | grep -q "type cgroup2"; then
    echo "[+] cgroup v2 already active"
else
    echo "[*] Mounting unified cgroup v2..."
    # পুরোনো মাউন্টগুলো ক্লিন করা (লেগেসি v1 সরিয়ে দেওয়া)
    umount -l "${CGROUP_ROOT}" 2>/dev/null
    
    # শুধুমাত্র cgroup2 মাউন্ট করা
    mount -t cgroup2 none "${CGROUP_ROOT}" || {
        echo "[-] Critical: Your kernel does not support Cgroup v2"
        exit 1
    }
fi

# ২. সব কন্ট্রোলার সাব-ট্রি তে এনেবল করা (systemd এর জন্য জরুরি)
if [ -f "${CGROUP_ROOT}/cgroup.subtree_control" ]; then
    echo "+cpuset +cpu +io +memory +pids +rdma" > "${CGROUP_ROOT}/cgroup.subtree_control" 2>/dev/null
fi

echo "[+] Cgroup v2 is ready for systemd"
exit 0
