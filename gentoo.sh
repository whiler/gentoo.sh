#!/bin/bash
# need GNU Coreutils support

SCRIPT="$(dirname "$(readlink -f $0)")"
source "${SCRIPT}/lib/log.sh"
source "${SCRIPT}/lib/functions.sh"

REQUIRED="parted pvcreate vgcreate vgchange lvcreate mkfs.vfat mkfs.ext4 mkswap swapon swapoff blkid shasum md5sum"
OPTIONAL="git"

VGNAME="gentoo"
SWAPLABEL="swap"
ROOTLABEL="root"
ARCH="amd64"
CPUCOUNT=
MEMSIZE=
ROOT="/mnt/gentoo"

DEV=
PLATFORM=
MIRRORS=
RSYNC=
STAGE3=
PORTAGE=
CONFIG=
HOSTNAME=
TIMEZONE=
PUBLICKEY=
MODE=

install() {
	if [[ -z "${CONFIG}" ]]; then
		LOGE "argument config required"
	elif [[ -z "${PUBLICKEY}" ]]; then
		LOGE "argument public-key required"
	fi

	if ! prepare-resource; then
		LOGE "prepare resource failed"
	elif ! prepare-disk; then
		LOGE "prepare disk failed"
	elif ! extract-resource; then
		LOGE "extract resource failed"
	elif ! config-gentoo; then
		LOGE "config gentoo failed"
	elif ! chroot-into-gentoo; then
		LOGE "chroot into gentoo failed"
	elif ! clean; then
		LOGW "clean failed"
	fi

	return 0
}

repair() {
	if ! open-disk; then
		LOGE "open disk failed"
	elif ! chroot-into-gentoo-for-repair; then
		LOGE "chroot failed"
	elif ! clean; then
		LOGW "clean failed"
	fi

	return 0
}

argparse() {
	for arg in "${@}"
	do
		case "${arg}" in 
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

			--mode=*)
				MODE="${arg#*=}"
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
	elif [[ ! -e "${SCRIPT}/platforms/${PLATFORM}.sh" ]]; then
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
