#!/bin/bash

# {{{ arguments
ARCH=
KEYWORDS=
PLATFORM=
MIRRORS=
RSYNC=
STAGE3=
PORTAGE=
FIRMWARE=
HOSTNAME=
TIMEZONE=
PUBLICKEY=
LUKS=
# }}}


main() {
    for arg in "${@}"
    do
        case "${arg}" in 
            --arch=*)
                ARCH="${arg#*=}"
                shift
                ;;

            --keywords=*)
                KEYWORDS="${arg#*=}"
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

            *)
                shift
                ;;
        esac

    done
}

main "${@}"
