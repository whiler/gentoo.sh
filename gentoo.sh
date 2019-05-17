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

PROFILE="default/linux/amd64/17.0"
VGNAME="gentoo"
DMCRYPTNAME="encrypted"
SWAPLABEL="swap"
ROOTLABEL="root"
ARCH="amd64"
MARCH=${ARCH}
CPUCOUNT=
ROOT="/mnt/gentoo"
CHROOT=true
BOOTUUID=
CRYPTUUID=
SWAPUUID=
ROOTUUID=

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
	local succ
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
	elif [[ ! -z "${CHROOT}" ]]; then
		if ! prepare-chroot; then
			LOGW "prepare chroot failed"
		elif ! chroot-into-gentoo; then
			LOGW "chroot into gentoo failed"
		else
			succ=true
		fi
	else
		succ=true
	fi

	if test ! -z "${succ}" && ! custom-gentoo; then
		LOGW "custom gentoo failed"
	fi

	return 0
}

repair() {
	if ! open-disk; then
		LOGW "open disk failed"
	elif [[ ! -z "${CHROOT}" ]]; then
		if ! prepare-chroot; then
			LOGW "prepare chroot failed"
		elif ! chroot-into-gentoo-for-repair; then
			LOGW "chroot failed"
		fi
	else
		pushd "${ROOT}"
			/bin/bash
		popd
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
	elif ! source "${SCRIPT}/platforms/${PLATFORM}.sh"; then
		LOGE "source ${SCRIPT}/platforms/${PLATFORM}.sh failed"
	elif ! check-platform-arguments; then
		LOGE "check platform ${PLATFORM} arguments failed"
	elif ! init-platform; then
		LOGE "init platform ${PLATFORM} failed"
	elif [[ 0 -ne ${UID} ]]; then
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

	if ! clean; then
		LOGW "clean failed"
	fi

	LOGI "enjoy gentoo"
}

main "${@}"
