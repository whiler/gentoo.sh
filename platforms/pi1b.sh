#!/bin/bash
# ARMv6-compatible processor [410fb767] revision 7 (ARMv7), cr=00c5387d
# Raspberry Pi Model B Rev 2
# BCM2835 SoC
# 512 MB RAM
# 
# The partition table must be MSDOS
# The first partition (/boot) must be vfat fat32
#
# Q: close device failed: Remote I/O error
# A: dd if=/dev/zero of=/dev/sdx

RUNNINGDEV=/dev/mmcblk0
ROOTFS=f2fs
DEVTAB=msdos
ARCH="arm"
MARCH="armv6j_hardfp"
CANCHROOT=
ENABLEBIOS=

check-platform-arguments() {
	local ret=0
	if [[ -z "${KERNEL}" ]]; then
		LOGW "kernel is required"
		ret=1
	elif [[ ! -f "${KERNEL}" ]]; then
		LOGW "kernel ${KERNEL} No such file"
		ret=1
	elif [[ ! -s "${KERNEL}" ]]; then
		LOGW "kernel ${KERNEL} is empty"
		ret=1
	fi
	return ${ret}
}

init-platform() {
	return 0
}

config-platform() {
	LOGI "config Raspberry Pi"
	
	LOGD "generating /boot/cmdline.txt"
	cat << EOF | paste --serial --delimiters=" " - > "${ROOT}/boot/cmdline.txt"
dwc_otg.lpm_enable=0
console=ttyAMA0,115200
kgdboc=ttyAMA0,115200
console=tty1
root=$(getfsdev "${ROOTDEV}")
rootfstype=${ROOTFS}
elevator=deadline
rootwait
EOF

	LOGD "generating /boot/config.txt"
	cat > "${ROOT}/boot/config.txt" << EOF
arm_freq=900
core_freq=333
sdram_freq=450
over_voltage=2
force_turbo=1
gpu_mem=16
enable_uart=1
EOF

	return 0
}

custom-gentoo() {
	LOGI "generating todo.sh"

	sed --in-place \
		--expression="s/curve25519-sha256@libssh.org,ecdh-sha2-nistp521,ecdh-sha2-nistp384,ecdh-sha2-nistp256,//" \
		--expression="s/,umac-128@openssh.com//" \
		"${ROOT}/etc/ssh/sshd_config"
	sed --in-place \
		--expression='s/^s0:\(.*\)/# s0:\1/' \
		--expression='s/^s1:\(.*\)/# s1:\1/' \
		"${ROOT}/etc/inittab"
	sed --in-place \
		--expression='s/^#rc_sys=""/rc_sys=""/' \
		"${ROOT}/etc/rc.conf"
	test -L "${ROOT}/etc/runlevels/boot/hwclock" && rm "${ROOT}/etc/runlevels/boot/hwclock"
	test ! -e "${ROOT}/etc/runlevels/boot/swclock" && ln --symbolic --force /etc/init.d/swclock "${ROOT}/etc/runlevels/boot/swclock"
	test ! -e "${ROOT}/etc/runlevels/default/busybox-ntpd" && ln --symbolic --force /etc/init.d/busybox-ntpd "${ROOT}/etc/runlevels/default/busybox-ntpd"
	if [[ ! -e "${ROOT}/etc/init.d/net.eth0" ]]; then
		ln --symbolic --force net.lo "${ROOT}/etc/init.d/net.eth0"
		ln --symbolic --force /etc/init.d/net.eth0 "${ROOT}/etc/runlevels/default/net.eth0"
	fi

	mkdir --parents "${ROOT}/etc/modules-load.d"
	echo "configs" >> "${ROOT}/etc/modules-load.d/configs.conf"

	cat > "${ROOT}/root/todo.sh" << DOCHERE
#!/bin/bash
# generated at $(date)

/usr/sbin/locale-gen
/usr/bin/eselect locale set en_US.UTF-8
/usr/sbin/env-update && source /etc/profile

/usr/bin/emerge --sync
/usr/sbin/perl-cleaner --all
/usr/bin/emerge --emptytree --newuse --update --deep --ask --tree --verbose world

/usr/bin/emerge --autounmask-write app-admin/sudo app-misc/tmux sys-power/cpupower sys-apps/rng-tools raspberrypi-userland net-wireless/wpa_supplicant sys-process/cronie app-admin/sysklogd app-editors/vim
/usr/bin/emerge                    app-admin/sudo app-misc/tmux sys-power/cpupower sys-apps/rng-tools raspberrypi-userland net-wireless/wpa_supplicant sys-process/cronie app-admin/sysklogd app-editors/vim
/sbin/rc-update add cronie default
/sbin/rc-update add sysklogd boot
/sbin/rc-update add cpupower default
/sbin/rc-update add rngd boot
/sbin/rc-update --update

/sbin/rc-service sysklogd start
/sbin/rc-service cronie start

cat > /etc/conf.d/cpupower << EOF
START_OPTS="--governor ondemand"
STOP_OPTS="--governor performance"
EOF
/sbin/rc-service cpupower start

echo "RNGD_OPTS=\"-o /dev/random -r /dev/hwrng\"" > /etc/conf.d/rngd
echo "modules=\"bcm2708-rng\"" >> /etc/conf.d/modules
echo "export PATH=\$PATH:/opt/vc/bin" > /etc/bash/bashrc.d/userland
echo "ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=wheel" >> /etc/wpa_supplicant/wpa_supplicant.conf
echo "update_config=1" >> /etc/wpa_supplicant/wpa_supplicant.conf
echo "wpa_supplicant_wlan0=\"-D wext\"" >> /etc/conf.d/net
ln -sf /etc/init.d/net.lo /etc/init.d/net.wlan0
emerge --update --newuse --deep --with-bdeps=y @world
emerge -avtuDN @preserved-rebuild
emerge -avtuDN --depclean

eclean-dist --deep
DOCHERE
    return 0
}
