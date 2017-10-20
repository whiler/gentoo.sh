#!/bin/bash

source "${SCRIPT}/lib/common.sh"

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
			yellow "Warning! command '${cmd}' not found"
		fi
	done

	return "${ret}"
}

init-arch() {
	return 0
}

init-platform() {
	return 0
}

check-arch() {
	return 0
}

check-platform() {
	return 0
}

check-stage3() {
	local stage3="${1}"
	local chk=0
	local filename="$(basename "${stage3}")"

	if [[ -e "${stage3}" && -e "${stage3}.DIGESTS" ]]; then
		pushd "$(dirname "${stage3}")"
			chk="$(shasum -c "${filename}.DIGESTS" 2>/dev/null | grep "${filename}:" | grep -c "OK")"
		popd
	fi
	
	if [[ 1 -eq "${chk}" ]]; then
		return 0
	else
		return 1
	fi
}

prepare-stage3() {
	local pattern="[0-9]\+/stage3-${_ARCH}-[0-9]\+.tar.bz2"
	local path=
	local filename=
	local url=
	local stage3=
	if [[ -z "${_STAGE3}" ]]; then
		for mirror in ${_MIRRORS[@]};
		do
			path="$(curl --silent "${mirror}/releases/${_ARCH}/autobuilds/latest-stage3.txt" | grep "${pattern}" | cut -d " " -f 1)"
			url="${mirror}/releases/${_ARCH}/autobuilds/${path}"
			filename="$(basename "${path}")"
			stage3="${SCRIPT}/resources/${filename}"

			if check-stage3 "${stage3}"; then
				_STAGE3="${stage3}"
				break
			fi

			debug "downloading ${url}"
			curl --silent --location --output "${stage3}" "${url}" && curl --silent --location --output "${stage3}.DIGESTS" "${url}.DIGESTS"

			if check-stage3 "${stage3}"; then
				_STAGE3="${stage3}"
				break
			else
				warn "check sum failed"
				rm "${stage3}" "${stage3}.DIGESTS"
			fi
		done
	fi
	if [[ -e "${_STAGE3}" ]]; then
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
		pushd "$(dirname "${portage}")"
			if md5sum -c "${filename}.md5sum" > /dev/null; then
				ret=0
			else
				ret=1
			fi
		popd
	fi

	return "${ret}"
}

prepare-portage() {
	local filename="portage-latest.tar.bz2"
	local portage="${SCRIPT}/resources/${filename}"
	local url=
	if [[ -z "${_PORTAGE}" ]]; then
		for mirror in ${_MIRRORS[@]};
		do
			url="${mirror}/snapshots/portage-latest.tar.bz2"

			if check-portage "${portage}"; then
				_PORTAGE="${portage}"
				break
			fi

			debug "downloading ${url}"
			curl --silent --location --output "${portage}" "${url}" && curl --silent --location --output "${portage}.md5sum" "${url}.md5sum"

			if check-portage "${portage}"; then
				_PORTAGE="${portage}"
				break
			else
				warn "check sum failed"
				rm "${portage}" "${portage}.md5sum"
			fi
		done
	fi
	if [[ -e "${_PORTAGE}" ]]; then
		return 0
	else
		return 1
	fi
}

prepare-resource() {
	local ret=0
	if ! prepare-stage3; then
		warn "prepare stage3 failed"
		ret=1
	elif ! prepare-portage; then
		warn "prepare portage failed"
		ret=1
	fi
    return "${ret}"
}

prepare-disk() {
	local keyfile="$(mktemp)"
	local cryptname="encrypted"
	local vgname="vg"

	parted --script --align=optimal "${_DEV}" mktable gpt
	parted --align=optimal "${_DEV}" <<EOF
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
	until [[ -e "${_DEV}3" ]]
	do
		sleep 0.3
	done

	modprobe {dm-mod,dm-crypt,aes,sha256,cbc}
	head -1 "${_LUKS}" | tr --delete "\r\n" | tr --delete "\r" | tr --delete "\n" > "${keyfile}"
	yes | cryptsetup luksFormat --key-file="${keyfile}" "${_DEV}3"
	cryptsetup luksOpen --key-file="${keyfile}" "${_DEV}3" "${cryptname}"
	rm "${keyfile}"

	pvcreate "/dev/mapper/${cryptname}"
	vgcreate "${vgname}" "/dev/mapper/${cryptname}"
	lvcreate --size="${MEMSIZE}" --name=swap "${vgname}"
	lvcreate --extents=100%FREE --name=root "${vgname}"

	mkfs.vfat -F 32 -n Boot "${_DEV}2"
	mkswap --force --label="swap" "/dev/${vgname}/swap"
	mkfs.ext4 -L "root" "/dev/${vgname}/root"

	swapon "/dev/${vgname}/swap"
	mkdir --parents "${ROOT}"
	mount "/dev/${vgname}/root" "${ROOT}"
	mkdir --parents "${ROOT}/boot"
	mount "${_DEV}2" "${ROOT}/boot"

	SWAPUUID="$(blkid -s UUID -t LABEL="swap" | cut -d "\"" -f 2)"
    ROOTUUID="$(blkid -s UUID -t LABEL="root" | cut -d "\"" -f 2)"

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

