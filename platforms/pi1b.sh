#!/bin/bash
# Raspberry Pi Model B Rev 2
# BCM2835 SoC
# 512 MB RAM
# ARMv6-compatible processor rev 7 (v6l)
# 

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
EOF

	return 0
}

custom-gentoo() {
	LOGI "generating todo.sh"

    cat > "${ROOT}/root/todo.sh" << DOCHERE
#!/bin/bash
# generated at $(date)

/etc/init.d/busybox-ntpd start

test -e /proc/config.gz && /bin/zcat /proc/config.gz > /boot/kernel.config

/usr/sbin/locale-gen
/usr/bin/eselect locale set en_US.UTF-8
/usr/sbin/env-update && source /etc/profile

/usr/bin/emerge --sync
/usr/bin/emerge --autounmask-write net-misc/ntp net-misc/dropbear app-admin/sudo app-misc/tmux sys-power/cpupower sys-apps/rng-tools raspberrypi-userland net-wireless/wpa_supplicant sys-process/cronie app-admin/sysklogd app-editors/vim
/usr/bin/emerge                    net-misc/ntp net-misc/dropbear app-admin/sudo app-misc/tmux sys-power/cpupower sys-apps/rng-tools raspberrypi-userland net-wireless/wpa_supplicant sys-process/cronie app-admin/sysklogd app-editors/vim
/sbin/rc-update add cronie default
/sbin/rc-update add ntp-client default
/sbin/rc-update add busybox-ntpd default
/sbin/rc-update add sysklogd boot
/sbin/rc-update add dropbear default
/sbin/rc-update add swclock boot
/sbin/rc-update add cpupower default
/sbin/rc-update add rngd boot
/sbin/rc-update del sshd
/sbin/rc-update del hwclock boot
/sbin/rc-update --update
/sbin/rc-service ntp-client start
/sbin/rc-service sysklogd start
/sbin/rc-service cronie start

ln --symbolic /usr/bin/dbscp /usr/bin/scp

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
/usr/bin/emerge --emptytree --newuse --update --deep --ask --tree --verbose world
emerge --update --newuse --deep --with-bdeps=y @world
emerge -avtuDN @preserved-rebuild
emerge -avtuDN --depclean

perl-cleaner --all

eclean-dist --deep
DOCHERE
    return 0
}
