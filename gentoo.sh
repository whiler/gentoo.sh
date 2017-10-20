#!/bin/bash
# need GNU Coreutils support

SCRIPT="$(dirname $0)"
source "${SCRIPT}/lib/common.sh"
source "${SCRIPT}/lib/functions.sh"

REQUIRED="parted pvcreate vgcreate vgchange lvcreate cryptsetup mkfs.vfat mkswap swapon swapoff modprobe blkid shasum md5sum"
OPTIONAL="mkfs.ext4 git"

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
FIRMWARE=
CONFIG=
HOSTNAME=
TIMEZONE=
PUBLICKEY=
LUKS=
MODE=

install() {
	if [[ -z "${FIRMWARE}" && -z "${CONFIG}" ]]; then
		error "argument firmware or config required"
	elif [[ -z "${PUBLICKEY}" ]]; then
		error "argument public-key required"
	fi

	if ! prepare-resource; then
		error "prepare resource failed"
	fi

	if ! prepare-disk; then
		error "prepare disk failed"
	fi

	if ! extract-resource; then
		error "extract resource failed"
	fi

	if ! config-gentoo; then
		error "config gentoo failed"
	fi

	if ! chroot-into-gentoo; then
		error "chroot into gentoo failed"
	fi

	if ! clean; then
		warn "clean failed"
	fi

	return 0
}

repair() {
	open-disk
	chroot-into-gentoo-for-repair
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

            --firmware=*)
                FIRMWARE="${arg#*=}"
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

            --luks=*)
                LUKS="${arg#*=}"
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

	PLATFORM="${PLATFORM:="generic"}"
	MIRRORS="${MIRRORS:="http://distfiles.gentoo.org/"}"
	RSYNC="${RSYNC:="rsync.gentoo.org"}"
	HOSTNAME="${HOSTNAME:="gentoo"}"
	TIMEZONE="${TIMEZONE:="GMT"}"
	MODE="${MODE:="install"}"

	return 0
}

main() {
	argparse "${@}"

	if [[ -z "${DEV}" ]]; then
		error "argument dev required"
	elif [[ -e "${DEV}" ]]; then
		error "no such dev ${DEV}"
	elif [[ ! -b "${DEV}" ]]; then
		error "dev ${DEV} must be block device"
	elif [[ ! -e "${SCRIPT}/platforms/${PLATFORM}.sh" ]]; then
		error "unsupported platform ${PLATFORM}"
	else
		source "${SCRIPT}/platforms/${PLATFORM}.sh"
		if ! check-platform-arguments; then
			error "check platform ${PLATFORM} arguments failed"
		elif ! init-platform; then
			error "init platform ${PLATFORM} failed"
		fi
	fi

	if [[ 0 -ne ${UID} ]]; then
		error "root privilege required"
	elif ! check-runtime; then
		error "check runtime failed"
	fi
	
	if [[ "install" == "${MODE}" ]]; then
		install
	elif [[ "repair" == "${MODE}" ]]; then
		repair
	else
		warn "What do you mean?"
	fi

	info "enjoy gentoo"
}

main "${@}"
