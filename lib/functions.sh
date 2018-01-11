#!/bin/bash

source "${SCRIPT}/lib/log.sh"

check-runtime() {
	local ret=0

	for cmd in ${REQUIRED[@]}
	do
		if ! which "${cmd}" > /dev/null; then
			red "Error! command '${cmd}' not found"
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

check-platform-arguments() {
	return 0
}

init-platform() {
	return 0
}

check-stage3() {
	local stage3="${1}"
	local chk=0
	local filename="$(basename "${stage3}")"

	if [[ -e "${stage3}" && -e "${stage3}.DIGESTS" ]]; then
		pushd "$(dirname "${stage3}")" > /dev/null
			chk="$(shasum --check "${filename}.DIGESTS" 2>/dev/null | grep "${filename}:" | grep -c "OK")"
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
				rm -f "${stage3}" "${stage3}.DIGESTS"
			fi
		done
	fi
	if [[ -e "${STAGE3}" ]]; then
		return 0
	else
		return 1
	fi
}

extract-stage3() {
	tar --extract --preserve-permissions --xattrs-include="*.*" --numeric-owner --file "${STAGE3}" --directory "${ROOT}"
	return $?
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
				rm -f "${portage}" "${portage}.md5sum"
			fi
		done
	fi
	if [[ -e "${PORTAGE}" ]]; then
		return 0
	else
		return 1
	fi
}

extract-portage() {
	tar --extract --xz --file "${PORTAGE}" --directory "${ROOT}/usr"
	return $?
}

prepare-resource() {
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
	vgchange --activate=y "${VGNAME}"

	swapon "/dev/${VGNAME}/swap"

	mkdir --parents "${ROOT}"
	mount "/dev/${VGNAME}/root" "${ROOT}"

	mkdir --parents "${ROOT}/boot"
	mount "${DEV}2" "${ROOT}/boot"

	return 0
}

prepare-disk() {
	parted --script --align=opt "${DEV}" "mktable gpt"
	parted --align=opt "${DEV}" <<EOF
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
	until [[ -e "${DEV}3" ]]
	do
		sleep 0.3
	done

	pvcreate "${DEV}3"
	vgcreate "${VGNAME}" "${DEV}3"
	lvcreate --size="${MEMSIZE}" --name=swap "${VGNAME}"
	lvcreate --extents=100%FREE --name=root "${VGNAME}"

	mkfs.vfat -F 32 -n BOOT "${DEV}2"
	mkswap --force --label="${SWAPLABEL}" "/dev/${VGNAME}/swap"
	mkfs.ext4 -L "${ROOTLABEL}" "/dev/${VGNAME}/root"

	open-disk

    return 0
}

extract-resource() {
	local ret=0

	if ! extract-stage3; then
		LOGW "extract stage3 failed"
		ret=1
	elif ! extract-portage; then
		LOGW "extract portage failed"
		ret=1
	fi

    return "${ret}"
}

config-gentoo() {
	sed -i -e "s/CFLAGS=\"-O2 -pipe\"/CFLAGS=\"-march=native -O2 -pipe\"/" "${ROOT}/etc/portage/make.conf"

	echo "MAKEOPTS=\"-j${CPUCOUNT}\"" >> "${ROOT}/etc/portage/make.conf"

	if [[ ! -z "${MIRRORS}" && "http://distfiles.gentoo.org/" != "${MIRRORS}" ]]; then
		echo "GENTOO_MIRRORS=\"${MIRRORS}\"" >> "${ROOT}/etc/portage/make.conf"
	fi

	mkdir --parents "${ROOT}/etc/portage/repos.conf"
	cp "${ROOT}/usr/share/portage/config/repos.conf" "${ROOT}/etc/portage/repos.conf/gentoo.conf"
	if [[ ! -z "${RSYNC}" && "rsync.gentoo.org" != "${RSYNC}" ]]; then
		sed -i -e "s/rsync.gentoo.org/${RSYNC}/" "${ROOT}/etc/portage/repos.conf/gentoo.conf"
	fi

	cp --dereference /etc/resolv.conf "${ROOT}/etc/"

	echo "${TIMEZONE}" > "${ROOT}/etc/timezone"
	cp "${ROOT}/usr/share/zoneinfo/${TIMEZONE}" "${ROOT}/etc/localtime"

	echo "LINGUAS=\"en_US\"" >> "${ROOT}/etc/portage/make.conf"
	echo "LC_COLLATE=\"C\"" >>     "${ROOT}/etc/env.d/02locale"
	echo "LANG=\"en_US.UTF-8\"" >> "${ROOT}/etc/env.d/02locale"
	echo "en_US.UTF-8 UTF-8" >> "${ROOT}/etc/locale.gen"

	sed -i -e "s/localhost/${HOSTNAME}/" "${ROOT}/etc/conf.d/hostname"
	cat > "${ROOT}/etc/hosts" <<EOF
127.0.0.1 ${HOSTNAME} localhost
::1 ${HOSTNAME} localhost
EOF

	sed -i -e "s/root:\*:10770:0:::::/root::10770:0:::::/" "${ROOT}/etc/shadow"

	mkdir --parents "${ROOT}/root/.ssh"
	cp --dereference "${PUBLICKEY}" "${ROOT}/root/.ssh/authorized_keys"
	chmod 0600 "${ROOT}/root/.ssh/authorized_keys"

	cat > "${ROOT}/etc/fstab" <<EOF
${DEV}2 /boot auto noauto,noatime 1 2
UUID=$(blkid -s UUID -o value -t LABEL="${SWAPLABEL}") none swap sw      0 0
UUID=$(blkid -s UUID -o value -t LABEL="${ROOTLABEL}") /    ext4 noatime 0 1
EOF

	cp --dereference "${CONFIG}" "${ROOT}/kernel.config"

	echo "GRUB_PLATFORMS=\"efi-64 pc\"" >> "${ROOT}/etc/portage/make.conf"

    return 0
}

prepare-chroot() {
	mount --types proc /proc ${ROOT}/proc
	mount --rbind /sys ${ROOT}/sys
	mount --make-rslave ${ROOT}/sys
	mount --rbind /dev ${ROOT}/dev
	mount --make-rslave ${ROOT}/dev 
	test -L /dev/shm && rm /dev/shm && mkdir /dev/shm && mount --types tmpfs --options nosuid,nodev,noexec shm /dev/shm && chmod 1777 /dev/shm
	return 0
}

chroot-into-gentoo-for-repair() {
	prepare-chroot
	LOGI "chroot"

	chroot "${ROOT}" /bin/bash

	return 0
}

chroot-into-gentoo() {
	prepare-chroot
	LOGI "chroot"

	chroot "${ROOT}" /bin/bash <<EOF
env-update && source /etc/profile
emerge --quiet sys-apps/pciutils sys-kernel/genkernel sys-kernel/linux-firmware =sys-kernel/gentoo-sources-4.9.72 =sys-boot/grub-2.02
mv /kernel.config /usr/src/linux/.config
echo "GRUB_CMDLINE_LINUX=\"dolvm\"" >> /etc/default/grub
pushd /usr/src/linux/
make && make modules_install && make install
popd
genkernel --lvm --install initramfs
grub-install --target=i386-pc "${DEV}"
grub-install --target=x86_64-efi --efi-directory=/boot --removable
grub-mkconfig -o /boot/grub/grub.cfg
EOF

    return 0
}

clean() {
	cd
	LOGI "clean"
	umount -l ${ROOT}/dev{/shm,/pts,}
	umount -R ${ROOT}
    return 0
}
