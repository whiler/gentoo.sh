#!/bin/bash

source "${SCRIPT}/lib/log.sh"

getcpucount() {
	grep --count processor /proc/cpuinfo
}

getmemsize() {
	local ret=
	local size=2
	local KB=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
	if [[ 262144 -ge ${KB} ]]; then
		ret=256
	elif [[ 524288 -ge ${KB} ]]; then
		ret=512
	elif [[ 1048576 -ge ${KB} ]]; then
		ret=1024
	else
		until [[ $((size * 1048576)) -ge ${KB} ]]
		do
			size=$((size + 1))
		done
		ret=$((1024 * size))
	fi
	echo ${ret}
}

check-runtime() {
	local ret=0

	for cmd in ${REQUIRED[@]}
	do
		if ! which "${cmd}" > /dev/null; then
			LOGE "Error! command '${cmd}' not found"
			ret=1
		fi
	done

	for cmd in ${OPTIONAL[@]}
	do
		if ! which "${cmd}" > /dev/null; then
			LOGW "command '${cmd}' not found"
		fi
	done

	return "${ret}"
}

check-stage3() {
	local stage3="${1}"
	local chk=0
	local filename="$(basename "${stage3}")"

	if [[ -e "${stage3}" && -e "${stage3}.DIGESTS" ]]; then
		pushd "$(dirname "${stage3}")" > /dev/null
			chk="$(shasum --check "${filename}.DIGESTS" 2>/dev/null | grep "${filename}:" | grep --count "OK")"
		popd > /dev/null
	fi

	if [[ 1 -eq "${chk}" ]]; then
		return 0
	else
		return 1
	fi
}

prepare-stage3() {
	local path=
	local filename=
	local url=
	local stage3=
	if [[ -z "${STAGE3}" ]]; then
		for mirror in ${MIRRORS[@]}
		do
			url="${mirror%%/}/releases/${ARCH}/autobuilds/latest-stage3-${ARCH}.txt"
			path="$(curl --silent "${url}" | grep --invert-match --extended-regexp "^#" | cut --delimiter=" " --fields=1)"
			if [[ -z "${path}" ]]; then
				LOGW "query the latest-stage3-${ARCH} from ${mirror} failed"
				continue
			fi
			url="${mirror%%/}/releases/${ARCH}/autobuilds/${path}"
			filename="$(basename "${path}")"
			stage3="${SCRIPT}/resources/${filename}"

			if check-stage3 "${stage3}"; then
				STAGE3="${stage3}"
				break
			fi

			LOGD "downloading ${url}"
			curl --silent --location --output "${stage3}" "${url}" && curl --silent --location --output "${stage3}.DIGESTS" "${url}.DIGESTS"

			if check-stage3 "${stage3}"; then
				STAGE3="${stage3}"
				break
			else
				LOGW "check sum failed"
				rm --force "${stage3}" "${stage3}.DIGESTS"
			fi
		done
	fi
	if [[ -e "${STAGE3}" ]]; then
		return 0
	else
		return 1
	fi
}

check-portage() {
	local portage="${1}"
	local ret=1
	local filename="$(basename "${portage}")"

	if [[ -e "${portage}" && -e "${portage}.md5sum" ]]; then
		pushd "$(dirname "${portage}")" > /dev/null
			if md5sum --check "${filename}.md5sum" > /dev/null; then
				ret=0
			else
				ret=1
			fi
		popd > /dev/null
	fi

	return "${ret}"
}

prepare-portage() {
	local filename="portage-latest.tar.xz"
	local portage="${SCRIPT}/resources/${filename}"
	local url=
	if [[ -z "${PORTAGE}" ]]; then
		for mirror in ${MIRRORS[@]}
		do
			url="${mirror%%/}/snapshots/${filename}"

			if check-portage "${portage}"; then
				PORTAGE="${portage}"
				break
			fi

			LOGD "downloading ${url}"
			curl --silent --location --output "${portage}" "${url}" && curl --silent --location --output "${portage}.md5sum" "${url}.md5sum"

			if check-portage "${portage}"; then
				PORTAGE="${portage}"
				break
			else
				LOGW "check sum failed"
				rm --force "${portage}" "${portage}.md5sum"
			fi
		done
	fi
	if [[ -e "${PORTAGE}" ]]; then
		return 0
	else
		return 1
	fi
}


prepare-resource() {
	LOGI "prepare resource"
	local ret=0
	if ! prepare-stage3; then
		LOGW "prepare stage3 failed"
		ret=1
	elif ! prepare-portage; then
		LOGW "prepare portage failed"
		ret=1
	fi
    return "${ret}"
}

open-disk() {
	LOGI "open disk"
	local keypath=

	mkdir --parents "${ROOT}"

	if [[ -z "${ENABLEDMCRYPT}" && -z "${ENABLELVM}" ]]; then
		until [[ -e "${DEV}3" ]]
		do
			sleep 0.3
		done
		if [[ ! -z "${ENABLESWAP}" ]]; then
			swapon "${DEV}3"

			mount "${DEV}4" "${ROOT}"
		else
			mount "${DEV}3" "${ROOT}"
		fi
	else
		lvscan

		if [[ ! -z "${ENABLEDMCRYPT}" && ! -e "/dev/mapper/${DMCRYPTNAME}" ]]; then
			keypath="$(mktemp)"
			head -1 "${DMCRYPTKEY}" | tr --delete "\r\n" | tr --delete "\r" | tr --delete "\n" > "${keypath}"
			if ! cryptsetup luksOpen --key-file="${keypath}" "${DEV}3" "${DMCRYPTNAME}"; then
				LOGE "luksOpen ${DEV}3 failed"
			fi
			rm "${keypath}"
		fi

		until [[ -e "/dev/${VGNAME}" ]]
		do
			vgchange --activate=y "/dev/${VGNAME}"
			sleep 0.3
		done

		if [[ ! -z "${ENABLESWAP}" ]]; then
			until [[ -e "/dev/${VGNAME}/${SWAPLABEL}" ]]
			do
				lvchange --activate=y "/dev/${VGNAME}/${SWAPLABEL}"
				sleep 0.3
			done
			swapon "/dev/${VGNAME}/${SWAPLABEL}"
		fi

		until [[ -e "/dev/${VGNAME}/${ROOTLABEL}" ]]
		do
			lvchange --activate=y "/dev/${VGNAME}/${ROOTLABEL}"
			sleep 0.3
		done
		mount "/dev/${VGNAME}/${ROOTLABEL}" "${ROOT}"
	fi

	mkdir --parents "${ROOT}/boot"
	mount "${DEV}2" "${ROOT}/boot"

	return 0
}

prepare-disk() {
	LOGI "prepare disk"
	local memsize=$(getmemsize)
	local offset=$((67 + ${memsize}))
	local cmds=
	local linuxdev=
	local keypath=

	if [[ -z "${ENABLEDMCRYPT}" && -z "${ENABLELVM}" ]]; then
		if [[ ! -z "${ENABLESWAP}" ]]; then
			cmds="$(cat <<EOF
unit mib
mkpart primary 1 3
name 1 grub
set 1 bios_grub on
mkpart ESI fat32 3 67
name 2 boot
set 2 boot on
mkpart primary linux-swap 67 ${offset}
name 3 swap
mkpart primary ext4 ${offset} 100%
name 4 root
quit
EOF
)"
		else
			cmds="$(cat <<EOF
unit mib
mkpart primary 1 3
name 1 grub
set 1 bios_grub on
mkpart ESI fat32 3 67
name 2 boot
set 2 boot on
mkpart primary ext4 67 100%
name 3 root
quit
EOF
)"
		fi
	else
		cmds="$(cat <<EOF
unit mib
mkpart primary 1 3
name 1 grub
set 1 bios_grub on
mkpart ESI fat32 3 67
name 2 boot
set 2 boot on
mkpart primary 67 100%
name 3 linux
quit
EOF
)"
		lvscan
		test -e "/dev/${VGNAME}/${SWAPLABEL}" && lvremove --force "/dev/${VGNAME}/${SWAPLABEL}"
		test -e "/dev/${VGNAME}/${ROOTLABEL}" && lvremove --force "/dev/${VGNAME}/${ROOTLABEL}"
		test -e "/dev/${VGNAME}" && vgremove --force "${VGNAME}"
	fi

	if ! parted --script --align=opt "${DEV}" "mktable gpt"; then
		LOGE "initialize ${DEV} failed"
	elif ! echo "${cmds}" | parted --align=opt "${DEV}"; then
		LOGE "partion  ${DEV} failed"
	fi

	until [[ -e "${DEV}2" && -e "${DEV}3" ]]
	do
		sleep 0.3
	done

	if ! mkfs.vfat -F 32 -n BOOT "${DEV}2"; then
		LOGE "format boot failed"
	else
		if [[ -z "${ENABLEDMCRYPT}" && -z "${ENABLELVM}" ]]; then
			if [[ ! -z "${ENABLESWAP}" ]]; then
				if ! mkswap --force --label="${SWAPLABEL}" "${DEV}3"; then
					LOGE "mkswap failed"
				elif ! mkfs.ext4 -F -L "${ROOTLABEL}" "${DEV}4"; then
					LOGE "mkfs.ext4 failed"
				fi
			elif ! mkfs.ext4 -F -L "${ROOTLABEL}" "${DEV}3"; then
				LOGE "mkfs.ext4 failed"
			fi
		else
			if [[ -z "${ENABLEDMCRYPT}" ]]; then
				linuxdev="${DEV}3"
			else
				keypath="$(mktemp)"
				head -1 "${DMCRYPTKEY}" | tr --delete "\r\n" | tr --delete "\r" | tr --delete "\n" > "${keypath}"
				if ! cryptsetup luksFormat --batch-mode --key-file="${keypath}" "${DEV}3"; then
					LOGE "luksFormat ${DEV}3 failed"
				elif ! cryptsetup luksOpen --key-file="${keypath}" "${DEV}3" "${DMCRYPTNAME}"; then
					LOGE "luksOpen ${DEV}3 failed"
				fi
				rm "${keypath}"
				linuxdev="/dev/mapper/${DMCRYPTNAME}"
			fi
			if ! pvcreate --force --force --yes "${linuxdev}"; then
				LOGE "pvcreate on ${linuxdev} failed"
			elif ! vgcreate "${VGNAME}" "${linuxdev}"; then
				LOGE "vgcreate ${VGNAME} ${linuxdev} failed"
			fi
			if [[ ! -z "${ENABLESWAP}" ]]; then
				if ! lvcreate --yes --size="${memsize}M" --name="${SWAPLABEL}" "${VGNAME}"; then
					LOGE "lvcreate failed"
				elif ! mkswap --force --label="${SWAPLABEL}" "/dev/${VGNAME}/${SWAPLABEL}"; then
					LOGE "mkswap failed"
				fi
			fi
			if ! lvcreate --yes --extents=100%FREE --name="${ROOTLABEL}" "${VGNAME}"; then
				LOGE "lvcreate failed"
			elif ! mkfs.ext4 -F -L "${ROOTLABEL}" "/dev/${VGNAME}/${ROOTLABEL}"; then
				LOGE "mkfs.ext4 failed"
			fi
		fi
	fi

    return 0
}

extract-resource() {
	LOGI "extract resource"
	local ret=0

	if ! tar --extract --preserve-permissions --xattrs-include="*.*" --numeric-owner --file "${STAGE3}" --directory "${ROOT}"; then
		LOGW "extract stage3 failed"
		ret=1
	elif ! tar --extract --xz --file "${PORTAGE}" --directory "${ROOT}/usr"; then
		LOGW "extract portage failed"
		ret=1
	fi

    return "${ret}"
}

config-gentoo() {
	LOGI "config gentoo"
	sed --in-place --expression="s/CFLAGS=\"-O2 -pipe\"/CFLAGS=\"-march=native -O2 -pipe\"/" "${ROOT}/etc/portage/make.conf"

	echo "MAKEOPTS=\"-j$(($(getcpucount) * 2 + 1))\"" >> "${ROOT}/etc/portage/make.conf"

	if [[ ! -z "${MIRRORS}" && "http://distfiles.gentoo.org/" != "${MIRRORS}" ]]; then
		echo "GENTOO_MIRRORS=\"${MIRRORS}\"" >> "${ROOT}/etc/portage/make.conf"
	fi
	if [[ ! -z "${DEBUG}" ]]; then
		echo "PORTAGE_BINHOST=\"http://10.0.2.2:10086/packages/\"" >> "${ROOT}/etc/portage/make.conf"
	fi

	mkdir --parents "${ROOT}/etc/portage/repos.conf"
	cp "${ROOT}/usr/share/portage/config/repos.conf" "${ROOT}/etc/portage/repos.conf/gentoo.conf"
	if [[ ! -z "${RSYNC}" && "rsync.gentoo.org" != "${RSYNC}" ]]; then
		sed --in-place --expression="s/rsync.gentoo.org/${RSYNC}/" "${ROOT}/etc/portage/repos.conf/gentoo.conf"
	fi

	echo "${TIMEZONE}" > "${ROOT}/etc/timezone"
	cp "${ROOT}/usr/share/zoneinfo/${TIMEZONE}" "${ROOT}/etc/localtime"

	echo "LINGUAS=\"en_US\"" >> "${ROOT}/etc/portage/make.conf"
	echo "LC_COLLATE=\"C\"" >>     "${ROOT}/etc/env.d/02locale"
	echo "LANG=\"en_US.UTF-8\"" >> "${ROOT}/etc/env.d/02locale"
	echo "en_US.UTF-8 UTF-8" >> "${ROOT}/etc/locale.gen"

	sed --in-place --expression="s/localhost/${HOSTNAME}/" "${ROOT}/etc/conf.d/hostname"
	cat > "${ROOT}/etc/hosts" <<EOF
127.0.0.1 ${HOSTNAME} localhost
::1 ${HOSTNAME} localhost
EOF

	sed --in-place --expression="s/root:\*:10770:0:::::/root::10770:0:::::/" "${ROOT}/etc/shadow"

	mkdir --parents "${ROOT}/root/.ssh"
	cp --dereference "${PUBLICKEY}" "${ROOT}/root/.ssh/authorized_keys"
	chmod 0600 "${ROOT}/root/.ssh/authorized_keys"
	if [[ -z "${ENABLESWAP}" ]]; then
		cat > "${ROOT}/etc/fstab" <<EOF
${DEV}2            /boot auto noauto,noatime 1 2
LABEL=${ROOTLABEL} /     ext4 noatime        0 1
EOF
	else
		cat > "${ROOT}/etc/fstab" <<EOF
${DEV}2            /boot auto noauto,noatime 1 2
LABEL=${SWAPLABEL} none  swap sw             0 0
LABEL=${ROOTLABEL} /     ext4 noatime        0 1
EOF
	fi

	cp --dereference "${CONFIG}" "${ROOT}/kernel.config"

	echo "GRUB_PLATFORMS=\"efi-64 pc\"" >> "${ROOT}/etc/portage/make.conf"

	ln --symbolic --force /proc/self/mounts "${ROOT}/etc/mtab"

	mkdir --parents "${ROOT}/etc/portage/env"
	echo "MAKEOPTS=\"-j1\"" >> "${ROOT}/etc/portage/env/singleton"
	echo "dev-libs/boost singleton" >> "${ROOT}/etc/portage/package.env"
	echo "dev-util/cmake singleton" >> "${ROOT}/etc/portage/package.env"
	echo "sys-block/thin-provisioning-tools singleton" >> "${ROOT}/etc/portage/package.env"

	mkdir --parents "${ROOT}/etc/portage/package.use"
	echo "sys-kernel/genkernel-next cryptsetup" >> "${ROOT}/etc/portage/package.use/genkernel-next"

    return 0
}

prepare-chroot() {
	LOGI "prepare chroot"

	cp --dereference --remove-destination --force /etc/resolv.conf "${ROOT}/etc/"

	mount --types proc /proc ${ROOT}/proc

	mount --rbind /sys ${ROOT}/sys
	mount --make-rslave ${ROOT}/sys

	mount --rbind /dev ${ROOT}/dev
	mount --make-rslave ${ROOT}/dev

	test -L /dev/shm && rm /dev/shm && mkdir /dev/shm && mount --types tmpfs --options nosuid,nodev,noexec shm /dev/shm && chmod 1777 /dev/shm
	return 0
}

chroot-into-gentoo-for-repair() {
	LOGI "chroot into gentoo for repair"

	chroot "${ROOT}" /bin/bash

	return $?
}

chroot-into-gentoo() {
	LOGI "chroot into gentoo"

	local cmdline=
	local opts=
	local profile="default/linux/amd64/17.0"

	if [[ ! -z "${ENABLELVM}" && ! "${cmdline}" =~ dolvm ]]; then
		cmdline="${cmdline} dolvm"
	fi
	if [[ ! -z "${ENABLEDMCRYPT}" ]]; then
		if [[ ! "${cmdline}" =~ dolvm ]]; then
			cmdline="${cmdline} dolvm"
		fi
		if [[ ! "${cmdline}" =~ crypt_root=${DEV}3 ]]; then
			cmdline="${cmdline} crypt_root=${DEV}3"
		fi
	fi
	if [[ ! -z "${ENABLESYSTEMD}" ]]; then
		if [[ ! "${cmdline}" =~ init=/usr/lib/systemd/systemd ]]; then
			cmdline="${cmdline} init=/usr/lib/systemd/systemd"
		fi
		if [[ ! "${profile}" =~ /systemd ]]; then
			profile="${profile}/systemd"
		fi
	fi
	if [[ ! -z "${DEBUG}" ]]; then
		opts="--getbinpkg"
	fi

	chroot "${ROOT}" /bin/bash <<EOF
eselect profile set "${profile}"
env-update && source /etc/profile

emerge --quiet --deep --newuse ${opts} @world
emerge --quiet ${opts} sys-apps/pciutils sys-kernel/genkernel-next sys-kernel/linux-firmware sys-fs/cryptsetup =sys-kernel/gentoo-sources-4.9.76-r1 =sys-boot/grub-2.02
emerge --quiet --depclean

mv /kernel.config /usr/src/linux/.config
pushd /usr/src/linux/
make --quiet --jobs=$(($(getcpucount) * 2 + 1)) && make --quiet modules_install && make --quiet install
popd

genkernel --loglevel=0 --udev --lvm --luks --install initramfs

echo "GRUB_CMDLINE_LINUX=\"${cmdline}\"" >> /etc/default/grub
echo "GRUB_DEVICE_UUID=$(blkid -s UUID -o value -t LABEL="${ROOTLABEL}")" >> /etc/default/grub
grub-install --target=i386-pc "${DEV}"
grub-install --target=x86_64-efi --efi-directory=/boot --removable
grub-mkconfig --output=/boot/grub/grub.cfg
EOF

	if [[ ! -z "${ENABLESYSTEMD}" ]]; then
		chroot "${ROOT}" /bin/bash <<EOF
env-update && source /etc/profile

systemd-machine-id-setup

echo "[Match]" >>   /etc/systemd/network/50-dhcp.network
echo "Name=en*" >>  /etc/systemd/network/50-dhcp.network
echo "[Network]" >> /etc/systemd/network/50-dhcp.network
echo "DHCP=yes" >>  /etc/systemd/network/50-dhcp.network
systemctl enable systemd-networkd.service

ln --no-dereference --symbolic --force /run/systemd/resolve/resolv.conf /etc/resolv.conf
systemctl enable systemd-resolved.service

systemctl enable sshd.service
EOF
	else
		chroot "${ROOT}" /bin/bash <<EOF
env-update && source /etc/profile

for ifname in \$(ls -l /sys/class/net/ | grep pci | cut -d " " -f 9); do
	echo "config_\${ifname}=dhcp" >> /etc/conf.d/net
	ln --symbolic --force net.lo "/etc/init.d/net.\${ifname}"
	ln --symbolic --force "/etc/init.d/net.\${ifname}" "/etc/runlevels/boot/net.\${ifname}"
done

ln --symbolic --force /etc/init.d/sshd /etc/runlevels/default/sshd
EOF
	fi
	return 0
}

clean() {
	LOGI "clean"
	
	local inSystemd=
	if [[ 1 -lt $(ps -efL | grep --count "/lib/systemd/systemd-timesyncd") ]]; then
		inSystemd=Y
	fi

	# resolve (Logical volume * contains a filesystem in use.)
	# https://ask.fedoraproject.org/en/question/10427/lvm-issue-with-lvremove-logical-volume-contains-a-filesystem-in-use/
	# https://wiki.archlinux.org/index.php/systemd-timesyncd
	if [[ ! -z "${inSystemd}" ]]; then
		timedatectl set-ntp false
		systemctl stop systemd-timedated.service
	fi

	umount --recursive --lazy "${ROOT}"


	if [[ -z "${ENABLEDMCRYPT}" && -z "${ENABLELVM}" && ! -z "${ENABLESWAP}" ]]; then
		swapoff "${DEV}3"
	else
		if [[ ! -z "${ENABLESWAP}" ]]; then
			swapoff "/dev/${VGNAME}/${SWAPLABEL}"
		fi
		test -e "/dev/${VGNAME}/${SWAPLABEL}" && lvchange --activate=n "/dev/${VGNAME}/${SWAPLABEL}"
		test -e "/dev/${VGNAME}/${ROOTLABEL}" && lvchange --activate=n "/dev/${VGNAME}/${ROOTLABEL}"
		test -e "/dev/${VGNAME}" && vgchange --activate=n "/dev/${VGNAME}"
		test -e "/dev/mapper/${DMCRYPTNAME}" && cryptsetup luksClose "/dev/mapper/${DMCRYPTNAME}"
	fi

	if [[ ! -z "${inSystemd}" ]]; then
		systemctl start systemd-timedated.service
		timedatectl set-ntp true
	fi

    return 0
}
