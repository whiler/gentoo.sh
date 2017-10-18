#!/bin/bash

source "lib/common.sh"
source "lib/functions.sh"

# {{{ arguments
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
# }}}


main() {
# {{{ get arguments from command line
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
# }}}
# {{{ fill default arguments
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
# }}}
# {{{ check required arguments
	if [[ -z "${_DEV}" ]]; then
		error "argument dev required"
	elif [[ -z "${_PUBLICKEY}" ]]; then
		error "argument public-key required"
	fi
# }}}

	if [[ ! -e "archs/${_ARCH}.sh" ]]; then
		error "unsupported arch ${_ARCH}"
	else
		source "archs/${_ARCH}.sh"
	fi

	if [[ ! -e "platforms/${_PLATFORM}.sh" ]]; then
		error "unsupported platform ${_PLATFORM}"
	else
		source "platforms/${_PLATFORM}.sh"
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
