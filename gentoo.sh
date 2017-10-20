#!/bin/bash
# need GNU Coreutils support

SCRIPT="$(dirname $0)"
source "${SCRIPT}/lib/common.sh"
source "${SCRIPT}/lib/functions.sh"

REQUIRED="parted pvcreate vgcreate vgchange lvcreate cryptsetup mkfs.vfat mkswap swapon swapoff modprobe blkid shasum md5sum"
OPTIONAL="mkfs.ext4 git"

MEMSIZE=
ROOT="/mnt/gentoo"

_DEV=
_ARCH=
_PLATFORM=
_MIRRORS=
_RSYNC=
_STAGE3=
_PORTAGE=
_FIRMWARE=
_CONFIG=
_HOSTNAME=
_TIMEZONE=
_PUBLICKEY=
_LUKS=

main() {
    for arg in "${@}"
    do
        case "${arg}" in 
            --dev=*)
                _DEV="${arg#*=}"
                shift
                ;;

            --arch=*)
                _ARCH="${arg#*=}"
                shift
                ;;

            --platform=*)
                _PLATFORM="${arg#*=}"
                shift
                ;;

            --mirrors=*)
                _MIRRORS="${arg#*=}"
                shift
                ;;

            --rsync=*)
                _RSYNC="${arg#*=}"
                shift
                ;;

            --stage3=*)
                _STAGE3="${arg#*=}"
                shift
                ;;

            --portage=*)
                _PORTAGE="${arg#*=}"
                shift
                ;;

            --firmware=*)
                _FIRMWARE="${arg#*=}"
                shift
                ;;

            --config=*)
                _CONFIG="${arg#*=}"
                shift
                ;;

            --hostname=*)
                _HOSTNAME="${arg#*=}"
                shift
                ;;

            --timezone=*)
                _TIMEZONE="${arg#*=}"
                shift
                ;;

            --public-key=*)
                _PUBLICKEY="${arg#*=}"
                shift
                ;;

            --luks=*)
                _LUKS="${arg#*=}"
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
	_ARCH="${_ARCH:=${arch}}"

	local platform="$(uname -s)"
	if [[ "Darwin" == "${platform}" ]]; then
		platform="mbp"
	else
		platform="generic"
	fi
	_PLATFORM="${_PLATFORM:=${platform}}"

	_MIRRORS="${_MIRRORS:="http://distfiles.gentoo.org/"}"
	_RSYNC="${_RSYNC:="rsync.gentoo.org"}"
	_HOSTNAME="${_HOSTNAME:="gentoo"}"
	_TIMEZONE="${_TIMEZONE:="GMT"}"

	if [[ -z "${_DEV}" ]]; then
		error "argument dev required"
	elif [[ -z "${_FIRMWARE}" && -z "${_CONFIG}" ]]; then
		error "argument firmware or config required"
	elif [[ -z "${_PUBLICKEY}" ]]; then
		error "argument public-key required"
	fi

	if [[ ! -e "archs/${_ARCH}.sh" ]]; then
		error "unsupported arch ${_ARCH}"
	else
		source "archs/${_ARCH}.sh"
		if ! init-arch; then
			error "init arch failed"
		elif ! check-arch; then
			error "check arch failed"
		fi
	fi

	if [[ ! -e "platforms/${_PLATFORM}.sh" ]]; then
		error "unsupported platform ${_PLATFORM}"
	else
		source "platforms/${_PLATFORM}.sh"
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
