#!/bin/bash

REQUIRED="${REQUIRED} cryptsetup"
ENABLEDMCRYPT=Y
ENABLESWAP=Y
ENABLESYSTEMD=Y

check-platform-arguments() {
	return 0
}

init-platform() {
	modprobe {dm-mod,dm-crypt,aes,sha256,cbc}
	return $?
}
