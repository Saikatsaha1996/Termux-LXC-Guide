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
umount -Rl "${LXC_ROOTFS_PATH}" 2>/dev/null

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

# Configuration ফিক্স করা হয়েছে:
# ১. /dev/dri আনকমেন্ট করা হয়েছে এবং graphics গ্রুপ সেট করা হয়েছে (যা ID 1003)
# ২. /dev/snd আনকমেন্ট করা হয়েছে অডিওর জন্য
required_configuration='#Type Path               Mode User Group     Age Argument
# /etc/tmpfiles.d/required.lxc-setup.conf

# GPU/Direct Rendering (DRM)
d!     /dev/dri            0755 root graphics  -   -
c!     /dev/dri/card0      0666 root graphics  -   226:0
c!     /dev/dri/renderD128 0666 root graphics  -   226:128

# Android sound
d!     /dev/snd            0755 1000 audio     -   -

# Android Graphics/Memory
c!     /dev/kgsl-3d0       0666 1000 1000      -   237:0
c!     /dev/ion            0664 1000 1000      -   10:62

# Other essentials
c!     /dev/fuse           0600 root root      -   10:229
c!     /dev/ashmem         0666 root root      -   10:58
c!     /dev/loop-control   0600 root root      -   10:237'

echo "${required_configuration}" > "${LXC_ROOTFS_PATH}/etc/tmpfiles.d/required.lxc-setup.conf"

# Loop Device ফিক্স:
# Standard Linux-এ loop device এর major number ৭ এবং minor number সিরিয়ালি (০, ১, ২...) হয়।
# i * 8 সাধারণত প্রয়োজন হয় না, তাই সরাসরি i ব্যবহার করা হয়েছে।
for i in $(seq 0 255); do
  echo "b!     /dev/loop${i}  0660 root disk  -   7:${i}" >> "${LXC_ROOTFS_PATH}/etc/tmpfiles.d/required.lxc-setup.conf"
done

# সাউন্ড ডিভাইস ফিক্স (Loop Device এর মতো অটোমেটিক অ্যাড):
# এটি হোস্টের /dev/snd থেকে সব ডিভাইসের তথ্য নিয়ে tmpfiles.d এ যোগ করবে
if [ -d "/dev/snd" ]; then
  for snd_dev in /dev/snd/*; do
    dev_name=$(basename "$snd_dev")
    # মেজোর এবং মাইনর নম্বর বের করা (যেমন: 116:33)
    dev_info=$(stat -c "%t:%T" "$snd_dev")
    # হেক্সাডেসিমাল থেকে ডেসিমাল এ রূপান্তর
    major=$((0x${dev_info%:*}))
    minor=$((0x${dev_info#*:}))
    
    # কনফিগ ফাইলে এন্ট্রি যোগ করা (ইউজার ubuntu/1000 এবং গ্রুপ termux_audio/1005)
    echo "c!     /dev/snd/${dev_name}  0660 1000 1005  -   ${major}:${minor}" >> "${LXC_ROOTFS_PATH}/etc/tmpfiles.d/required.lxc-setup.conf"
  done
fi



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
