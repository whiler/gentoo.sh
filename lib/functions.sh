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
		for mirror in ${MIRRORS[@]};
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
		for mirror in ${MIRRORS[@]};
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

#SWAPUUID="$(blkid -s UUID -o value -t LABEL="swap")"
#ROOTUUID="$(blkid -s UUID -o value -t LABEL="root")"

	swapon "/dev/${VGNAME}/swap"
	mkdir --parents "${ROOT}"
	mount "/dev/${VGNAME}/root" "${ROOT}"
	mkdir --parents "${ROOT}/boot"
	mount "${DEV}2" "${ROOT}/boot"

    return 0
}

extract-resource() {
    return 0
}

config-gentoo() {
    return 0
}

chroot-into-gentoo() {
    return 0
}

clean() {
    return 0
}
