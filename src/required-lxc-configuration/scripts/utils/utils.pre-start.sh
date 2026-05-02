#!/usr/bin/env sh

# Pre-start script for LXC containers (Cgroup v2 fixed)

[ -n "${LXC_ROOTFS_PATH}" ] && [ -n "${LXC_CONFIG_FILE}" ] || {
  echo "Variable LXC_ROOTFS_PATH/LXC_CONFIG_FILE not set"
  exit 1
}

CONFIG_PATH="$(cd "$(dirname "${0}")"; cd ../../../..; pwd)"
CONFIG_BASENAME="$(basename "${CONFIG_PATH}")"

CGROUP_ROOT="/sys/fs/cgroup"

for cg in blkio cpu cpuacct cpuset devices freezer memory pids schedtune systemd; do
  if mount | grep -q "${CGROUP_ROOT}/${cg}"; then
    umount -l "${CGROUP_ROOT}/${cg}" 2>/dev/null
  fi
  rm -rf "${CGROUP_ROOT:?}/${cg}" 2>/dev/null
done

if ! mount | grep -q "on ${CGROUP_ROOT} type cgroup2"; then
  echo "[*] Attempting to mount cgroup v2..."
  mkdir -p "${CGROUP_ROOT}"
  mount -o remount,rw,nosuid,nodev,noexec,relatime none "${CGROUP_ROOT}" 2>/dev/null || \
  mount -t cgroup2 none "${CGROUP_ROOT}" || {
    echo "[-] Critical: Failed to mount cgroup2"
    mkdir -p "${CGROUP_ROOT}/unified"
    mount -t cgroup2 none "${CGROUP_ROOT}/unified" || exit 1
    CGROUP_ROOT="${CGROUP_ROOT}/unified"
  }
else
  echo "[+] cgroup v2 is already active at ${CGROUP_ROOT}"
fi

if [ -f "${CGROUP_ROOT}/cgroup.subtree_control" ]; then
  echo "[*] Enabling cgroup controllers..."
  for c in cpuset cpu io memory pids; do
    echo "+$c" > "${CGROUP_ROOT}/cgroup.subtree_control" 2>/dev/null
  done
fi

# binfmt_misc fix
if [ ! -f /proc/sys/fs/binfmt_misc/register ]; then
  mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc
fi

# Clean leftover mounts
# Sets correct DNS resolver to fix connectivity
sed -i -E 's/^( *#* *)?DNS=.*/DNS=8.8.8.8 1.1.1.1/g' "${LXC_ROOTFS_PATH}/etc/systemd/resolved.conf"

lxc-net start

# Adds Termux colors
sed -i '/TERM/d' "${LXC_ROOTFS_PATH}/etc/environment"
echo 'TERM="'${TERM}'"' >> "${LXC_ROOTFS_PATH}/etc/environment"

# Use PulseAudio for sound
sed -i '/PULSE_SERVER/d' "${LXC_ROOTFS_PATH}/etc/environment"
echo 'PULSE_SERVER="10.0.4.1:4713"' >> "${LXC_ROOTFS_PATH}/etc/environment"
su "${SUDO_USER}" -c "PATH='${PREFIX}/bin:${PATH}' HOME='${PREFIX}/var/run/lxc-pulse' pulseaudio --start --load='module-native-protocol-tcp auth-ip-acl=10.0.4.0/24 auth-anonymous=1' --exit-idle-time=-1"
restorecon -R "${PREFIX}/var/run/lxc-pulse"

# Remove redundant dialog
# http://c-nergy.be/blog/?p=12073
mkdir -p "${LXC_ROOTFS_PATH}/etc/polkit-1/localauthority/50-local.d"
chmod 755 "${LXC_ROOTFS_PATH}/etc/polkit-1/localauthority/50-local.d"

required_configuration='[Allow Colord all Users]
Identity=unix-user:*
Action=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile
ResultAny=no
ResultInactive=no
ResultActive=yes'

echo "${required_configuration}" > "${LXC_ROOTFS_PATH}/etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla"

# Makes non-funtional udevadm always return true, or else some packages and snaps gives errors when trying to install
if [ ! -e "${LXC_ROOTFS_PATH}/usr/bin/udevadm." ]; then
  mv -f "${LXC_ROOTFS_PATH}/usr/bin/udevadm" "${LXC_ROOTFS_PATH}/usr/bin/udevadm."
fi

required_configuration='#!/usr/bin/bash
/usr/bin/udevadm. "$@" || true'

echo "${required_configuration}" > "${LXC_ROOTFS_PATH}/usr/bin/udevadm"
chmod 755 "${LXC_ROOTFS_PATH}/usr/bin/udevadm"

# Copy temporary config files to rootfs /tmp
rm -rf "${LXC_ROOTFS_PATH}/tmp/${CONFIG_BASENAME}"
mkdir -p "${LXC_ROOTFS_PATH}/tmp"
cp -rf "${CONFIG_PATH}" "${LXC_ROOTFS_PATH}/tmp"

if [ -e "${LXC_ROOTFS_PATH}/usr/lib/systemd/system/lxc-net.service" ] || [ -f "${LXC_ROOTFS_PATH}/usr/libexec/lxc/lxc-net" ] || [ -f "${LXC_ROOTFS_PATH}/usr/lib/aarch64-linux-gnu/lxc/lxc-net" ] || [ -f "${LXC_ROOTFS_PATH}/usr/lib/arm-linux-gnu/lxc/lxc-net" ] || [ -f "${LXC_ROOTFS_PATH}/usr/lib/x86_64-linux-gnu/lxc/lxc-net" ] || [ -f "${LXC_ROOTFS_PATH}/usr/lib/x86-linux-gnu/lxc/lxc-net" ]; then
  LD_PRELOAD= chroot "${LXC_ROOTFS_PATH}" usr/bin/sh -c " \
    . '/tmp/${CONFIG_BASENAME}/src/required-lxc-configuration/scripts/utils/utils.set-env.sh'; \
    '/tmp/${CONFIG_BASENAME}/src/required-lxc-configuration/scripts/utils/utils.temp-mount.sh' mount; \
    '/tmp/${CONFIG_BASENAME}/src/required-lxc-configuration/scripts/utils/utils.lxc-net.configuration.sh'; \
    '/tmp/${CONFIG_BASENAME}/src/required-lxc-configuration/scripts/utils/utils.temp-mount.sh' umount; \
  "
fi

if [ -e "${LXC_ROOTFS_PATH}/usr/lib/systemd/system/waydroid-container.service" ] || [ -f "${LXC_ROOTFS_PATH}/usr/lib/waydroid/data/scripts/waydroid-net.sh" ] || [ -f "${LXC_ROOTFS_PATH}/var/lib/waydroid/waydroid.cfg" ]; then
  LD_PRELOAD= chroot "${LXC_ROOTFS_PATH}" usr/bin/sh -c " \
    . '/tmp/${CONFIG_BASENAME}/src/required-lxc-configuration/scripts/utils/utils.set-env.sh'; \
    '/tmp/${CONFIG_BASENAME}/src/required-lxc-configuration/scripts/utils/utils.temp-mount.sh' mount; \
    '/tmp/${CONFIG_BASENAME}/src/required-lxc-configuration/scripts/utils/utils.waydroid.configuration.sh'; \
    '/tmp/${CONFIG_BASENAME}/src/required-lxc-configuration/scripts/utils/utils.temp-mount.sh' umount; \
  "
fi

# Fixes iptables command as Android requires legacy mode
rm -rf "${LXC_ROOTFS_PATH}/usr/sbin/iptables" "${LXC_ROOTFS_PATH}/usr/sbin/ip6tables"
ln -nsf /usr/sbin/iptables-legacy "${LXC_ROOTFS_PATH}/usr/sbin/iptables"
ln -nsf /usr/sbin/ip6tables-legacy "${LXC_ROOTFS_PATH}/usr/sbin/ip6tables"

# Sets up container internals

mkdir -p "${LXC_ROOTFS_PATH}/etc/tmpfiles.d"
TMPFILE="${LXC_ROOTFS_PATH}/etc/tmpfiles.d/required.lxc-setup.conf"

echo "# Auto-generated full /dev mapping" > "$TMPFILE"

# ২. কোর ডিভাইসগুলো একবারে লিখুন
cat <<EOF >> "$TMPFILE"
c! /dev/null 0666 0 0 - 1:3
c! /dev/zero 0666 0 0 - 1:5
c! /dev/random 0666 0 0 - 1:8
c! /dev/urandom 0666 0 0 - 1:9
c! /dev/tty 0666 0 0 - 5:0
c! /dev/ptmx 0666 0 0 - 5:2
c! /dev/ashmem 0666 0 0 - 10:58
c! /dev/fuse 0600 0 0 - 10:229
c! /dev/loop-control 0600 0 0 - 10:237
EOF

# ৩. ডিরেক্টরি চেক
for d in dri snd input binderfs; do
  [ -d "/dev/$d" ] && echo "d! /dev/$d 0755 0 0 -" >> "$TMPFILE"
done

# ৪. ডিভাইস অ্যাড করার ফাংশন (উন্নত)
add_dev() {
  local dev="$1"
  [ -e "$dev" ] || return
  
  local name="${dev#/dev/}"
  case "$name" in
    pts/*|shm/*|fd|stdin|stdout|stderr|console) return ;;
  esac

  local dev_info=$(stat -c "%t:%T:%a:%u:%g" "$dev")
  IFS=':' read -r major_hex minor_hex perms uid gid <<< "$dev_info"
  
  local major=$((0x$major_hex))
  local minor=$((0x$minor_hex))
  local type="c"
  [ -b "$dev" ] && type="b"

  echo "$type! /dev/$name $perms $uid $gid - $major:$minor" >> "$TMPFILE"
}

# ৫. Find কমান্ডের আউটপুট প্রসেস করা
# এখানে পাইপলাইনের বদলে ফর-লুপ ব্যবহার করা নিরাপদ
for dev in $(find /dev -maxdepth 2 \( -type c -o -type b \) 2>/dev/null); do
  add_dev "$dev"
done

# ৬. লুপ ডিভাইস (০ থেকে ৭ পর্যন্ত রাখা ভালো, ২৫৫ অনেক বেশি)
for i in $(seq 0 7); do
  echo "b! /dev/loop${i} 0660 0 6 - 7:${i}" >> "$TMPFILE"
done

mkdir -p "${LXC_ROOTFS_PATH}/etc/systemd/system/multi-user.target.wants"
rm -rf "${LXC_ROOTFS_PATH}/usr/lib/required-lxc-configuration"
cp -rf "${LXC_ROOTFS_PATH}/tmp/${CONFIG_BASENAME}/src/required-lxc-configuration" "${LXC_ROOTFS_PATH}/usr/lib"
find "${LXC_ROOTFS_PATH}/etc/systemd/system" -maxdepth 1 -type l -name "required\.*\.service" -delete
find "${LXC_ROOTFS_PATH}/etc/systemd/system/multi-user.target.wants" -maxdepth 1 -type l -name "required\.*\.service" -delete

for i in $(find "${LXC_ROOTFS_PATH}/usr/lib/required-lxc-configuration/services" -maxdepth 1 -type f -name "required\.*\.service"); do
  service_name="$(basename "${i}")"
  ln -nsf "/usr/lib/required-lxc-configuration/services/${service_name}" "${LXC_ROOTFS_PATH}/etc/systemd/system/${service_name}"
  ln -nsf "/etc/systemd/system/${service_name}" "${LXC_ROOTFS_PATH}/etc/systemd/system/multi-user.target.wants/${service_name}"
done

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
mount -o remount,suid,dev "${LXC_ROOTFS_PATH}"

exit 0
