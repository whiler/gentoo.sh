#!/bin/bash

source "${SCRIPT}/lib/common.sh"

# {{{ check-runtime
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
# }}}
# {{{ stage3
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
# }}}
# {{{ portage
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
# }}}
prepare-resource() {
	prepare-stage3
	prepare-portage
    return 0
}

prepare-disk() {
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

