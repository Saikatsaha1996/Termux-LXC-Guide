#!/usr/bin/env sh

# Pre-start script for LXC containers (Cgroup v2 fixed)

[ -n "${LXC_ROOTFS_PATH}" ] && [ -n "${LXC_CONFIG_FILE}" ] || {
  echo "Variable LXC_ROOTFS_PATH/LXC_CONFIG_FILE not set"
  exit 1
}

CONFIG_PATH="$(cd "$(dirname "${0}")"; cd ../../../..; pwd)"
CONFIG_BASENAME="$(basename "${CONFIG_PATH}")"

CGROUP_ROOT="/sys/fs/cgroup"

# ✅ Ensure cgroup2 mounted (DO NOT recreate v1)
if ! mount | grep -q "type cgroup2"; then
  echo "[*] Mounting cgroup v2..."
  mkdir -p "${CGROUP_ROOT}"
  mount -t cgroup2 none "${CGROUP_ROOT}" || {
    echo "[-] Failed to mount cgroup2"
    exit 1
  }
else
  echo "[+] cgroup v2 already active"
fi

# ❌ REMOVE all v1 mounts (safe cleanup)
for cg in blkio cpu cpuacct cpuset devices freezer memory pids schedtune; do
  umount -l "${CGROUP_ROOT}/${cg}" 2>/dev/null
  rm -rf "${CGROUP_ROOT:?}/${cg}"
done

# ❌ REMOVE legacy systemd cgroup mount
umount -l "${CGROUP_ROOT}/systemd" 2>/dev/null

# binfmt_misc fix
if [ ! -f /proc/sys/fs/binfmt_misc/register ]; then
  mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc
fi

# Clean leftover mounts
umount -Rl "${LXC_ROOTFS_PATH}" 2>/dev/null

# DNS fix
sed -i -E 's/^( *#* *)?DNS=.*/DNS=8.8.8.8 1.1.1.1/g' \
  "${LXC_ROOTFS_PATH}/etc/systemd/resolved.conf"

# Network
lxc-net start

# TERM fix
sed -i '/TERM/d' "${LXC_ROOTFS_PATH}/etc/environment"
echo "TERM=${TERM}" >> "${LXC_ROOTFS_PATH}/etc/environment"

# PulseAudio
sed -i '/PULSE_SERVER/d' "${LXC_ROOTFS_PATH}/etc/environment"
echo 'PULSE_SERVER=10.0.4.1:4713' >> "${LXC_ROOTFS_PATH}/etc/environment"

su "${SUDO_USER}" -c "PATH='${PREFIX}/bin:${PATH}' \
HOME='${PREFIX}/var/run/lxc-pulse' \
pulseaudio --start \
--load='module-native-protocol-tcp auth-ip-acl=10.0.4.0/24 auth-anonymous=1' \
--exit-idle-time=-1"

# udevadm dummy fix
if [ ! -e "${LXC_ROOTFS_PATH}/usr/bin/udevadm." ]; then
  mv -f "${LXC_ROOTFS_PATH}/usr/bin/udevadm" \
        "${LXC_ROOTFS_PATH}/usr/bin/udevadm."
fi

cat > "${LXC_ROOTFS_PATH}/usr/bin/udevadm" << 'EOF'
#!/usr/bin/env bash
/usr/bin/udevadm. "$@" || true
EOF

chmod 755 "${LXC_ROOTFS_PATH}/usr/bin/udevadm"

# iptables legacy fix
rm -f "${LXC_ROOTFS_PATH}/usr/sbin/iptables"
ln -sf /usr/sbin/iptables-legacy \
       "${LXC_ROOTFS_PATH}/usr/sbin/iptables"

rm -f "${LXC_ROOTFS_PATH}/usr/sbin/ip6tables"
ln -sf /usr/sbin/ip6tables-legacy \
       "${LXC_ROOTFS_PATH}/usr/sbin/ip6tables"

# tmpfiles (minimal)
mkdir -p "${LXC_ROOTFS_PATH}/etc/tmpfiles.d"

cat > "${LXC_ROOTFS_PATH}/etc/tmpfiles.d/lxc.conf" <<EOF
c! /dev/fuse 0600 root root - 10:229
c! /dev/ashmem 0666 root root - 10:58
EOF

# password init (once)
if ! grep -Eq "^# RESET_PASSWORD_ONCE=done" "${LXC_CONFIG_FILE}"; then
  sed -i '/RESET_PASSWORD_ONCE/d' "${LXC_CONFIG_FILE}"
  LD_PRELOAD= chroot "${LXC_ROOTFS_PATH}" usr/bin/sh -c " \
    . '/tmp/${CONFIG_BASENAME}/src/required-lxc-configuration/scripts/utils/utils.set-env.sh'; \
    '/tmp/${CONFIG_BASENAME}/src/required-lxc-configuration/scripts/utils/utils.temp-mount.sh' mount; \
    echo password | sed 's/.*/\0\n\0/' | passwd root 2>/dev/null >/dev/null; \
    echo password | sed 's/.*/\0\n\0/' | passwd ubuntu 2>/dev/null >/dev/null; \
    '/tmp/${CONFIG_BASENAME}/src/required-lxc-configuration/scripts/utils/utils.temp-mount.sh' umount; \
  "
  echo "# RESET_PASSWORD_ONCE=done" >> "${LXC_CONFIG_FILE}"
fi

# Remove temporary config files from rootfs /tmp
rm -rf "${LXC_ROOTFS_PATH}/tmp/${CONFIG_BASENAME}"

# Sets temporary suid for the rootfs using bind mounts, otherwise normal users inside the container won't be able to use sudo commands
mount -B "${LXC_ROOTFS_PATH}" "${LXC_ROOTFS_PATH}"
mount -i -o remount,suid "${LXC_ROOTFS_PATH}"

exit 0
