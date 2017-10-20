#!/bin/bash
# need GNU Coreutils support

SCRIPT="$(dirname $0)"
source "${SCRIPT}/lib/common.sh"
source "${SCRIPT}/lib/functions.sh"

REQUIRED="parted pvcreate vgcreate vgchange lvcreate cryptsetup mkfs.vfat mkswap swapon swapoff modprobe blkid shasum md5sum"
OPTIONAL="mkfs.ext4 git"

CPUCOUNT=
MEMSIZE=
ROOT="/mnt/gentoo"

DEV=
ARCH=
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

main() {
    for arg in "${@}"
    do
        case "${arg}" in 
            --dev=*)
                DEV="${arg#*=}"
                shift
                ;;

            --arch=*)
                ARCH="${arg#*=}"
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

	local arch="$(uname -m)"
	if [[ "x86_64" == "${arch}" ]]; then
		arch="amd64"
	fi
	ARCH="${ARCH:=${arch}}"

	local platform="$(uname -s)"
	if [[ "Darwin" == "${platform}" ]]; then
		platform="mbp"
	else
		platform="generic"
	fi
	PLATFORM="${PLATFORM:=${platform}}"

	MIRRORS="${MIRRORS:="http://distfiles.gentoo.org/"}"
	RSYNC="${RSYNC:="rsync.gentoo.org"}"
	HOSTNAME="${HOSTNAME:="gentoo"}"
	TIMEZONE="${TIMEZONE:="GMT"}"
	MODE="${MODE:="install"}"

	if [[ -z "${DEV}" ]]; then
		error "argument dev required"
	elif [[ -z "${FIRMWARE}" && -z "${CONFIG}" ]]; then
		error "argument firmware or config required"
	elif [[ -z "${PUBLICKEY}" ]]; then
		error "argument public-key required"
	fi

	if [[ ! -e "archs/${ARCH}.sh" ]]; then
		error "unsupported arch ${ARCH}"
	else
		source "archs/${ARCH}.sh"
		if ! init-arch; then
			error "init arch failed"
		elif ! check-arch; then
			error "check arch failed"
		fi
	fi

	if [[ ! -e "platforms/${PLATFORM}.sh" ]]; then
		error "unsupported platform ${PLATFORM}"
	else
		source "platforms/${PLATFORM}.sh"
		if ! init-platform; then
			error "init platform failed"
		elif ! check-platform; then
			error "check platform failed"
		fi
	fi

	if [[ 0 -ne ${UID} ]]; then
		error "root privilege required"
	fi

	if ! check-runtime; then
		error "check runtime failed"
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

	info "enjoy gentoo"
}

main "${@}"
