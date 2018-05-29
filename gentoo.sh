#!/bin/bash
# need GNU Coreutils support

SCRIPT="$(dirname "$(readlink --canonicalize "$0")")"
source "${SCRIPT}/lib/log.sh"
source "${SCRIPT}/lib/functions.sh"

REQUIRED="parted mkfs.vfat mkfs.ext4 mkswap swapon swapoff shasum md5sum"
OPTIONAL=

# {{{ Features
ENABLEDMCRYPT=
ENABLELVM=
ENABLESWAP=
ENABLESYSTEMD=
# }}}

VGNAME="gentoo"
DMCRYPTNAME="encrypted"
SWAPLABEL="swap"
ROOTLABEL="root"
ARCH="amd64"
CPUCOUNT=
ROOT="/mnt/gentoo"
BOOTUUID=
CRYPTUUID=
SWAPUUID=
ROOTUUID=

# emerge --newuse --deep --oneshot --quiet $(grep 'completed emerge .* to /' /var/log/emerge.log | grep -o -E '[a-z]+-[a-z]+/[^ ]+' | sed -e 's/-[0-9].*$//' | sort -u)
# emerge --deep --buildpkgonly --quiet $(grep 'completed emerge .* to /' /var/log/emerge.log | grep -o -E '[a-z]+-[a-z]+/[^ ]+' | sed -e 's/-[0-9].*$//' | sort -u)
# usr/portage/packages
DEBUG=
DEV=
PLATFORM=
MIRRORS=
RSYNC=
STAGE3=
PORTAGE=
CONFIG=
KERNEL=
HOSTNAME=
TIMEZONE=
PUBLICKEY=
DMCRYPTKEY=
MODE=
USRNAME=

install() {
	if [[ -z "${CONFIG}" && -z "${KERNEL}" ]]; then
		LOGE "argument kernel/config required"
	elif [[ ! -z "${KERNEL}" && ! -f "${KERNEL}" ]]; then
		LOGE "kernel ${KERNEL} No such file"
	elif [[ ! -z "${CONFIG}" && ! -f "${CONFIG}" ]]; then
		LOGE "config ${CONFIG} No such file"
	elif [[ -z "${PUBLICKEY}" ]]; then
		LOGE "argument public-key required"
	elif [[ ! -f "${PUBLICKEY}" ]]; then
		LOGE "public-key ${PUBLICKEY} No such file"
	fi

	if ! prepare-resource; then
		LOGW "prepare resource failed"
	elif ! prepare-disk; then
		LOGW "prepare disk failed"
	elif ! open-disk; then
		LOGW "open disk failed"
	elif ! extract-resource; then
		LOGW "extract resource failed"
	elif ! config-gentoo; then
		LOGW "config gentoo failed"
	elif ! prepare-chroot; then
		LOGW "prepare chroot failed"
	elif ! chroot-into-gentoo; then
		LOGW "chroot into gentoo failed"
	elif ! custom-gentoo; then
		LOGW "custom gentoo failed"
	fi

	if ! clean; then
		LOGW "clean failed"
	fi

	return 0
}

repair() {
	if ! open-disk; then
		LOGW "open disk failed"
	elif ! prepare-chroot; then
		LOGW "prepare chroot failed"
	elif ! chroot-into-gentoo-for-repair; then
		LOGW "chroot failed"
	fi

	if ! clean; then
		LOGW "clean failed"
	fi

	return 0
}

argparse() {
	for arg in "${@}"
	do
		case "${arg}" in
			--debug=*)
				DEBUG="${arg#*=}"
				shift
				;;

			--dev=*)
				DEV="${arg#*=}"
				shift
				;;

			--platform=*)
				PLATFORM="${arg#*=}"
				shift
				;;

			--mirrors=*)
				MIRRORS="${arg#*=}"
				shift
				;;

			--rsync=*)
				RSYNC="${arg#*=}"
				shift
				;;

			--stage3=*)
				STAGE3="${arg#*=}"
				shift
				;;

			--portage=*)
				PORTAGE="${arg#*=}"
				shift
				;;

			--config=*)
				CONFIG="${arg#*=}"
				shift
				;;

			--kernel=*)
				KERNEL="${arg#*=}"
				shift
				;;

			--hostname=*)
				HOSTNAME="${arg#*=}"
				shift
				;;

			--timezone=*)
				TIMEZONE="${arg#*=}"
				shift
				;;

			--public-key=*)
				PUBLICKEY="${arg#*=}"
				shift
				;;

			--dmcrypt-key=*)
				DMCRYPTKEY="${arg#*=}"
				shift
				;;

			--mode=*)
				MODE="${arg#*=}"
				shift
				;;

			--username=*)
				USRNAME="${arg#*=}"
				shift
				;;

			*)
				shift
				;;
		esac

	done

	PLATFORM="${PLATFORM:="base"}"
	MIRRORS="${MIRRORS:="http://distfiles.gentoo.org/"}"
	RSYNC="${RSYNC:="rsync.gentoo.org"}"
	HOSTNAME="${HOSTNAME:="gentoo"}"
	TIMEZONE="${TIMEZONE:="UTC"}"
	MODE="${MODE:="install"}"
	USRNAME="${USRNAME:="gentoo"}"

	return 0
}

main() {
	argparse "${@}"

	if [[ -z "${DEV}" ]]; then
		LOGE "argument dev required"
	elif [[ ! -e "${DEV}" ]]; then
		LOGE "no such dev ${DEV}"
	elif [[ ! -b "${DEV}" ]]; then
		LOGE "dev ${DEV} must be block device"
	elif [[ ! -f "${SCRIPT}/platforms/${PLATFORM}.sh" ]]; then
		LOGE "unsupported platform ${PLATFORM}"
	else
		source "${SCRIPT}/platforms/${PLATFORM}.sh"
		if ! check-platform-arguments; then
			LOGE "check platform ${PLATFORM} arguments failed"
		elif ! init-platform; then
			LOGE "init platform ${PLATFORM} failed"
		fi
	fi

	if [[ 0 -ne ${UID} ]]; then
		LOGE "root privilege required"
	elif ! check-runtime; then
		LOGE "check runtime failed"
	fi

	if [[ "install" == "${MODE}" ]]; then
		install
	elif [[ "repair" == "${MODE}" ]]; then
		repair
	else
		LOGW "What do you mean?"
	fi

	LOGI "enjoy gentoo"
}

main "${@}"
