#!/bin/bash

source "${SCRIPT}/lib/log.sh"

REQUIRED="${REQUIRED} cryptsetup"
ENABLEDMCRYPT=Y
ENABLESWAP=Y
ENABLESYSTEMD=Y

check-platform-arguments() {
	local ret=0
	if [[ -z "${DMCRYPTKEY}" ]]; then
		LOGW "dmcrypt-key is required"
		ret=1
	fi
	return ${ret}
}

init-platform() {
	modprobe {dm-mod,dm-crypt,aes,sha256,cbc}
	return $?
}
