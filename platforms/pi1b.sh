#!/bin/bash
# Raspberry Pi Model B Rev 2
# BCM2835 SoC
# 512 MB RAM
# ARMv6-compatible processor rev 7 (v6l)
# 

ARCH="arm"
MARCH="armv6j_hardfp"
REQUIRED="${REQUIRED} mkfs.f2fs"
CANCHROOT=
ENABLEGRUB=

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
