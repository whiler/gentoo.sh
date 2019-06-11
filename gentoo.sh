#!/bin/bash

ABSROOT="$(dirname "$(readlink --canonicalize "$0")")"
export DTFMT="+[%Y-%m-%d %H:%M:%S %Z]"

CANCHROOT=true
ENABLEDMCRYPT=
RUNNINGDEV=/dev/sda
ROOTFS=ext4
DEVTAB=gpt
ENABLEBIOS=true
REQUIRED="fdisk parted mkfs.vfat mkswap swapon swapoff shasum md5sum"
OPTIONAL=
ENABLESYSTEMD=

PROFILE=default/linux/amd64/17.0
VGNAME=
DMCRYPTNAME=
SWAPLABEL=swap
ROOTLABEL=root
ARCH=amd64
MARCH=${ARCH}
ROOT=/mnt/gentoo
BOOTDEV=
CRYPTDEV=
SWAPDEV=
ROOTDEV=

DEBUG=
DEV=
PLATFORM=
MIRRORS=
RSYNC=
STAGE3=
PORTAGE=
CONFIG=
KERNEL=
NODENAME=
TIMEZONE=
PUBLICKEY=
DMCRYPTKEY=
MODE=
USRNAME=
MEMSIZE=
CPUCOUNT=

LOGD () { echo -e "$(date "${DTFMT}")" "[DEBUG]" "${@}"; }
export -f LOGD

LOGI () { echo -e "$(date "${DTFMT}")" "\033[32m[INFO]\033[0m" "${@}"; }
export -f LOGI

LOGW () { echo -e "$(date "${DTFMT}")" "\033[33m[WARN]\033[0m" "${@}"; }
export -f LOGW

LOGE () { echo -e "$(date "${DTFMT}")" "\033[31m[ERROR]\033[0m" "${@}"; }
export -f LOGE

argparse() {
	for arg in "${@}"; do
		case "${arg}" in
			--debug=*)
				DEBUG="${arg#*=}"
				shift
				;;

			--mem=*)
				MEMSIZE="${arg#*=}"
				shift
				;;

			--cpu=*)
				CPUCOUNT="${arg#*=}"
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
				NODENAME="${arg#*=}"
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
	NODENAME="${NODENAME:="gentoo"}"
	TIMEZONE="${TIMEZONE:="UTC"}"
	MODE="${MODE:="install"}"
	USRNAME="${USRNAME:="gentoo"}"
	CPUCOUNT="${CPUCOUNT:=$(getcpucount)}"
	MEMSIZE="${MEMSIZE:=$(getmemsize)}"

	return 0
}

check-dev() {
	if [[ -z "${1}" ]]; then
		LOGE "argument dev required"
	elif [[ ! -e "${1}" ]]; then
		LOGE "no such dev ${1}"
	elif [[ ! -b "${1}" ]]; then
		LOGE "dev ${1} must be block device"
	else
		return 0
	fi
	return 1
}

adjust-vgname() {
	local identifier=
	identifier="$(fdisk --list "${DEV}" | grep 'Disk identifier' | tail --bytes=8)"
	if [[ ! -z "${identifier}" ]]; then
		VGNAME="${identifier}"
		DMCRYPTNAME="${identifier}x"
	else
		VGNAME="gentoo"
		DMCRYPTNAME="encrypted"
	fi
}

check-platform() {
	if [[ ! -f "${ABSROOT}/platforms/${1}.sh" ]]; then
		LOGE "unsupported platform ${1}"
	elif ! source "${ABSROOT}/platforms/${1}.sh"; then
		LOGE "source ${ABSROOT}/platforms/${1}.sh failed"
	else
		return 0
	fi
	return 1
}

check-platform-arguments() {
	return 0
}

init-platform() {
	return 0
}

check-runtime() {
	local ret=0
	local requires="${REQUIRED} mkfs.${ROOTFS}"

	for cmd in ${requires}; do
		if ! hash "${cmd}"; then
			LOGE "command '${cmd}' not found"
			ret=1
		fi
	done

	for cmd in ${OPTIONAL}; do
		if ! hash "${cmd}"; then
			LOGW "command '${cmd}' not found"
		fi
	done

	return "${ret}"
}

install() {
	if [[ -z "${CONFIG}" && -z "${KERNEL}" ]]; then
		LOGE "argument kernel/config required"
	elif [[ ! -z "${KERNEL}" && ! -f "${KERNEL}" ]]; then
		LOGE "kernel ${KERNEL} No such file"
	elif [[ ! -z "${KERNEL}" && ! -s "${KERNEL}" ]]; then
		LOGE "kernel ${KERNEL} is empty"
	elif [[ ! -z "${CONFIG}" && ! -f "${CONFIG}" ]]; then
		LOGE "config ${CONFIG} No such file"
	elif [[ ! -z "${CONFIG}" && ! -s "${CONFIG}" ]]; then
		LOGE "config ${CONFIG} is empty"
	elif [[ -z "${PUBLICKEY}" ]]; then
		LOGE "argument public-key required"
	elif [[ ! -f "${PUBLICKEY}" ]]; then
		LOGE "public-key ${PUBLICKEY} No such file"
	elif [[ ! -s "${PUBLICKEY}" ]]; then
		LOGE "public-key ${PUBLICKEY} is empty"
	elif [[ ! -z "${ENABLEDMCRYPT}" && -z "${DMCRYPTKEY}" ]]; then
		LOGE "dmcrypt-key is required"
	elif [[ ! -z "${ENABLEDMCRYPT}" && ! -f "${DMCRYPTKEY}" ]]; then
		LOGE "dmcrypt-key ${DMCRYPTKEY} No such file"
	elif [[ ! -z "${ENABLEDMCRYPT}" && ! -s "${DMCRYPTKEY}" ]]; then
		LOGE "dmcrypt-key ${DMCRYPTKEY} is empty"
	elif ! prepare-resource; then
		LOGE "prepare resource failed"
	elif ! prepare-disk; then
		LOGE "prepare disk failed"
	elif ! open-disk; then
		LOGE "open disk failed"
	elif ! trap clean EXIT; then
		LOGE "register clean at EXIT failed"
	elif ! extract-resource; then
		LOGE "extract resource failed"
	elif ! config-platform; then
		LOGE "config platform failed"
	elif ! config-gentoo; then
		LOGE "config gentoo failed"
	elif test ! -z "${CANCHROOT}" && ! prepare-chroot; then
		LOGE "prepare chroot failed"
	elif test ! -z "${CANCHROOT}" && ! chroot-into-gentoo; then
		LOGE "chroot into gentoo failed"
	elif ! custom-gentoo; then
		LOGE "custom gentoo failed"
	else
		return 0
	fi

	return 1
}

repair() {
	adjust-vgname

	if ! open-disk; then
		LOGE "open disk failed"
	elif ! trap clean EXIT; then
		LOGE "register clean at EXIT failed"
	elif test ! -z "${CANCHROOT}" && ! prepare-chroot; then
		LOGE "prepare chroot failed"
	elif test ! -z "${CANCHROOT}" && ! chroot-into-gentoo-for-repair; then
		LOGE "chroot for repair failed"
	elif [[ -z "${CANCHROOT}" ]]; then
		pushd "${ROOT}"
			/bin/bash
		popd
		return 0
	else
		return 0
	fi

	return 1
}

prepare-resource() {
	LOGI "prepare resource"
	if ! prepare-stage3; then
		LOGW "prepare stage3 failed"
	elif ! prepare-portage; then
		LOGW "prepare portage failed"
	else
		return 0
	fi
    return 1
}

prepare-disk() {
	LOGI "prepare disk"

	local keypath=

	if ! make-partitions; then
		LOGE "make partitions failed"
		return 1
	fi

	until [[ -e "${BOOTDEV}" && -b "${BOOTDEV}" ]]; do
		sleep 0.3
	done
	sleep 1.3
	if ! mkfs.vfat -F 32 -n BOOT "${BOOTDEV}"; then
		LOGE "format boot failed"
		return 1
	fi

	if [[ ! -z "${ENABLEDMCRYPT}" ]]; then
		until [[ -e "${CRYPTDEV}" && -b "${CRYPTDEV}" ]]; do
			sleep 0.3
		done
		keypath="$(mktemp)"
		head -1 "${DMCRYPTKEY}" | tr --delete "\r\n" | tr --delete "\r" | tr --delete "\n" > "${keypath}"
		if ! cryptsetup luksFormat --batch-mode --key-file="${keypath}" "${CRYPTDEV}"; then
			LOGE "luksFormat ${CRYPTDEV} failed"
			rm "${keypath}"
			return 1
		elif ! cryptsetup luksOpen --key-file="${keypath}" "${CRYPTDEV}" "${DMCRYPTNAME}"; then
			LOGE "luksOpen ${CRYPTDEV} failed"
			rm "${keypath}"
			return 1
		fi
		rm "${keypath}"

		until [[ -e "/dev/mapper/${DMCRYPTNAME}" && -b "/dev/mapper/${DMCRYPTNAME}" ]]; do
			sleep 0.3
		done

		if ! pvcreate --force --force --yes "/dev/mapper/${DMCRYPTNAME}"; then
			LOGE "pvcreate on /dev/mapper/${DMCRYPTNAME} failed"
			return 1
		elif ! vgcreate "${VGNAME}" "/dev/mapper/${DMCRYPTNAME}"; then
			LOGE "vgcreate ${VGNAME} /dev/mapper/${DMCRYPTNAME} failed"
			return 1
		elif ! lvcreate --yes --size="${MEMSIZE}M" --name="${SWAPLABEL}" "${VGNAME}"; then
			LOGE "lvcreate ${SWAPLABEL} failed"
			return 1
		elif ! lvcreate --yes --extents=100%FREE --name="${ROOTLABEL}" "${VGNAME}"; then
			LOGE "lvcreate ${ROOTLABEL} failed"
			return 1
		else
			SWAPDEV="/dev/${VGNAME}/${SWAPLABEL}"
			ROOTDEV="/dev/${VGNAME}/${ROOTLABEL}"
		fi
	fi

	until [[ -e "${SWAPDEV}" && -b "${SWAPDEV}" ]]; do
		sleep 0.3
	done
	until [[ -e "${ROOTDEV}" && -b "${ROOTDEV}" ]]; do
		sleep 0.3
	done
	if ! mkswap --force --label="${SWAPLABEL}" "${SWAPDEV}"; then
		LOGE "mkswap ${SWAPDEV} failed"
		return 1
	elif ! mkrootfs "${ROOTDEV}"; then
		LOGE "mkfs.${ROOTFS} ${ROOTDEV} failed"
		return 1
	fi
    return 0
}

open-disk() {
	LOGI "open disk"
	local keypath=

	mkdir --parents "${ROOT}"

	if [[ ! -z "${ENABLEDMCRYPT}" ]]; then
		if [[ ! -z "${ENABLEBIOS}" ]]; then
			BOOTDEV=$(getpart "${DEV}" 2)
			CRYPTDEV=$(getpart "${DEV}" 3)
		else
			BOOTDEV=$(getpart "${DEV}" 1)
			CRYPTDEV=$(getpart "${DEV}" 2)
		fi
		SWAPDEV="/dev/${VGNAME}/${SWAPLABEL}"
		ROOTDEV="/dev/${VGNAME}/${ROOTLABEL}"

		if [[ ! -e "/dev/mapper/${DMCRYPTNAME}" ]]; then
			lvscan
			keypath="$(mktemp)"
			head -1 "${DMCRYPTKEY}" | tr --delete "\r\n" | tr --delete "\r" | tr --delete "\n" > "${keypath}"
			if ! cryptsetup luksOpen --key-file="${keypath}" "${CRYPTDEV}" "${DMCRYPTNAME}"; then
				LOGE "luksOpen ${CRYPTDEV} failed"
				rm "${keypath}"
				return 1
			fi
			rm "${keypath}"

		fi
		pvchange --allocatable=y --yes "/dev/mapper/${DMCRYPTNAME}"

		until [[ -e "/dev/mapper/${DMCRYPTNAME}" && -b "/dev/mapper/${DMCRYPTNAME}" ]]; do
			sleep 0.3
		done
		until [[ -e "/dev/${VGNAME}" ]]; do
			vgchange --activate=y "/dev/${VGNAME}"
			sleep 0.3
		done
		lvchange --activate=y "${SWAPDEV}"
		lvchange --activate=y "${ROOTDEV}"
		until [[ -e "${SWAPDEV}" ]]; do
			sleep 0.3
		done
		until [[ -e "${ROOTDEV}" ]]; do
			sleep 0.3
		done
	else
		if [[ ! -z "${ENABLEBIOS}" ]]; then
			BOOTDEV=$(getpart "${DEV}" 2)
			SWAPDEV=$(getpart "${DEV}" 3)
			ROOTDEV=$(getpart "${DEV}" 4)
		else
			BOOTDEV=$(getpart "${DEV}" 1)
			SWAPDEV=$(getpart "${DEV}" 2)
			ROOTDEV=$(getpart "${DEV}" 3)
		fi
	fi

	until [[ -e "${BOOTDEV}" && -e "${SWAPDEV}" && -e "${ROOTDEV}" ]]; do
		sleep 0.3
	done

	if ! swapon "${SWAPDEV}"; then
		LOGE "swapon failed"
		return 1
	elif ! mount "${ROOTDEV}" "${ROOT}"; then
		LOGE "mount root failed"
		return 1
	fi

	mkdir --parents "${ROOT}/boot"
	if ! mount "${BOOTDEV}" "${ROOT}/boot"; then
		LOGE "mount boot failed"
		return 1
	fi
	return 0
}

clean() {
	LOGI "clean"

	# fix unable to stat /etc/sudoers: Permission denied
	chmod 755 "${ROOT}"

	if [[ ! -z "${DEBUG}" && -e "${ROOT}/usr/src/linux/.config" ]]; then
		md5="$(md5sum "${ROOT}/usr/src/linux/.config" | cut --delimiter=" " --fields=1)"
		if [[ -e "${ROOT}/kernel.${md5}.tar.gz" && -s "${ROOT}/kernel.${md5}.tar.gz" ]]; then
			mkdir --parents "${ABSROOT}/resources/firmwares/${PLATFORM}"
			mv "${ROOT}/kernel.${md5}.tar.gz" "${ABSROOT}/resources/firmwares/${PLATFORM}/kernel.${md5}.tar.gz"
		fi
		test -e "${ROOT}/pack.gentoo.kernel.sh" && rm "${ROOT}/pack.gentoo.kernel.sh"
	fi

	if [[ ! -z "${ENABLESYSTEMD}" ]]; then
		ln --no-dereference --symbolic --force /run/systemd/resolve/resolv.conf "${ROOT}/etc/resolv.conf"
	fi

	local inSystemd
	if [[ 0 -lt $(pgrep --full --count "/lib/systemd/systemd-timesyncd") ]]; then
		inSystemd=true
	fi

	# resolve (Logical volume * contains a filesystem in use.)
	# https://ask.fedoraproject.org/en/question/10427/lvm-issue-with-lvremove-logical-volume-contains-a-filesystem-in-use/
	# https://wiki.archlinux.org/index.php/systemd-timesyncd
	if [[ ! -z "${inSystemd}" ]]; then
		timedatectl set-ntp false
		systemctl stop systemd-timedated.service
	fi

	if [[ 0 -lt $(mount | grep --count "${ROOT}") ]]; then
		umount --recursive --lazy "${ROOT}"
		swapoff "${SWAPDEV}"
		test -e "/dev/${VGNAME}/${SWAPLABEL}" && lvchange --activate=n "/dev/${VGNAME}/${SWAPLABEL}"
		test -e "/dev/${VGNAME}/${ROOTLABEL}" && lvchange --activate=n "/dev/${VGNAME}/${ROOTLABEL}"
		test -e "/dev/${VGNAME}" && vgchange --activate=n "/dev/${VGNAME}"
		test -e "/dev/mapper/${DMCRYPTNAME}" && cryptsetup luksClose "/dev/mapper/${DMCRYPTNAME}" && pvchange --allocatable=n --yes "/dev/mapper/${DMCRYPTNAME}"
	fi

	if [[ ! -z "${inSystemd}" ]]; then
		systemctl start systemd-timedated.service
		timedatectl set-ntp true
	fi

    return 0
}

extract-resource() {
	LOGI "extract resource"

	local md5=

	if [[ ! -z "${DEBUG}" ]]; then
		cp --dereference "${ABSROOT}/scripts/pack.gentoo.kernel.sh" "${ROOT}/pack.gentoo.kernel.sh"
		if [[ -z "${KERNEL}" ]]; then
			md5="$(md5sum "${CONFIG}" | cut --delimiter=" " --fields=1)"
			if [[ -f "${ABSROOT}/resources/firmwares/${PLATFORM}/kernel.${md5}.tar.gz" ]]; then
				KERNEL="${ABSROOT}/resources/firmwares/${PLATFORM}/kernel.${md5}.tar.gz"
				touch "${ROOT}/kernel.${md5}.tar.gz"
			fi
		fi
	fi

	if ! tar --extract --preserve-permissions --xattrs-include="*.*" --numeric-owner --file "${STAGE3}" --directory "${ROOT}"; then
		LOGE "extract stage3 failed"
	elif ! tar --extract --xz --file "${PORTAGE}" --directory "${ROOT}/usr"; then
		LOGE "extract portage failed"
	elif test -f "${KERNEL}" && ! tar --keep-directory-symlink --no-same-owner --extract --gzip --file="${KERNEL}" --directory="${ROOT}"; then
		LOGE "extract kernel failed"
	elif test ! -z "${CONFIG}" && test -f "${CONFIG}" && ! cp --dereference "${CONFIG}" "${ROOT}/kernel.config"; then
		LOGE "copy kernel config failed"
	else
		return 0
	fi

	return 1
}

config-platform() {
	return 0
}

config-gentoo() {
	LOGI "config gentoo"

	echo "USE=\"-bindist\"" >> "${ROOT}/etc/portage/make.conf"

	for d in env package.env package.accept_keywords package.accept_restrict package.keywords package.license package.mask package.properties package.unmask package.use repos.conf; do
		mkdir --parents "${ROOT}/etc/portage/${d}"
	done

	echo "MAKEOPTS=\"-j$((CPUCOUNT * 2 + 1))\"" >> "${ROOT}/etc/portage/make.conf"

	if [[ ! -z "${MIRRORS}" && "http://distfiles.gentoo.org/" != "${MIRRORS}" ]]; then
		echo "GENTOO_MIRRORS=\"${MIRRORS}\"" >> "${ROOT}/etc/portage/make.conf"
	fi

	echo "GRUB_PLATFORMS=\"efi-64 pc\"" >> "${ROOT}/etc/portage/make.conf"

	cp "${ROOT}/usr/share/portage/config/repos.conf" "${ROOT}/etc/portage/repos.conf/gentoo.conf"
	if [[ ! -z "${RSYNC}" && "rsync.gentoo.org" != "${RSYNC}" ]]; then
		sed --in-place --expression="s/rsync.gentoo.org/${RSYNC}/" "${ROOT}/etc/portage/repos.conf/gentoo.conf"
	fi

	echo "MAKEOPTS=\"-j1\"" >> "${ROOT}/etc/portage/env/singleton"
	for pkg in dev-libs/boost dev-util/cmake sys-block/thin-provisioning-tools sys-devel/binutils sys-devel/gcc; do
		echo "${pkg} singleton" > "${ROOT}/etc/portage/package.env/$(basename "${pkg}")"
	done

	if [[ ! -z "${ENABLEDMCRYPT}" ]]; then
		echo "sys-kernel/genkernel-next cryptsetup" >> "${ROOT}/etc/portage/package.use/genkernel-next"
	fi
	echo "net-firewall/ipset -modules" >> "${ROOT}/etc/portage/package.use/ipset"

	echo "LINGUAS=\"en_US\"" >> "${ROOT}/etc/portage/make.conf"
	echo "LC_COLLATE=\"C\"" >>     "${ROOT}/etc/env.d/02locale"
	echo "LANG=\"en_US.UTF-8\"" >> "${ROOT}/etc/env.d/02locale"
	echo "en_US.UTF-8 UTF-8" >> "${ROOT}/etc/locale.gen"
	echo "zh_CN.UTF-8 UTF-8" >> "${ROOT}/etc/locale.gen"

	echo "${TIMEZONE}" > "${ROOT}/etc/timezone"
	cp "${ROOT}/usr/share/zoneinfo/${TIMEZONE}" "${ROOT}/etc/localtime"

	echo "${NODENAME}" > "${ROOT}/etc/hostname"
	sed --in-place --expression="s/localhost/${NODENAME}/" "${ROOT}/etc/conf.d/hostname"
	cat > "${ROOT}/etc/hosts" <<EOF
127.0.0.1		${NODENAME} localhost

# The following lines are desirable for IPv6 capable hosts
::1		${NODENAME} localhost ip6-localhost ip6-loopback
ff02::1		ip6-allnodes
ff02::2		ip6-allrouters
EOF
	cat > "${ROOT}/etc/fstab" << EOF
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
$(getfsdev "${BOOTDEV}") /boot vfat noauto,noatime 1 2
$(getfsdev "${SWAPDEV}") none  swap sw             0 0
$(getfsdev "${ROOTDEV}") /     ${ROOTFS} noatime        0 1
EOF


	ln --symbolic --force /proc/self/mounts "${ROOT}/etc/mtab"

	x-chpasswd root "$(tr --delete --complement A-Za-z0-9_ < /dev/urandom | head --bytes=96 | xargs)"
	x-useradd "${USRNAME}" audio,cdrom,input,users,video,wheel
	x-chpasswd "${USRNAME}" "$(tr --delete --complement A-Za-z0-9_ < /dev/urandom | head --bytes=96 | xargs)"

	sed --in-place \
		--expression='/^auth\s\+sufficient\s\+pam_rootok.so/ a# trust users in the "wheel" group\nauth sufficient pam_wheel.so trust use_uid' \
		"${ROOT}/etc/pam.d/su"

	config-sshd
	cat "${PUBLICKEY}" >> "${ROOT}/home/${USRNAME}/.ssh/authorized_keys"

	cat > "${ROOT}/var/lib/iptables/rules-save" << EOF
*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
COMMIT

*mangle
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A PREROUTING -m conntrack --ctstate INVALID -m comment --comment "Block Invalid Packets" -j DROP
-A PREROUTING -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -m comment --comment "Block New Packets That Are Not SYN" -j DROP
-A PREROUTING -p tcp -m conntrack --ctstate NEW -m tcpmss ! --mss 536:65535 -m comment --comment "Block Uncommon MSS Values" -j DROP
-A PREROUTING -p tcp -m tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG NONE -m comment --comment "Block Packets With Bogus TCP Flags" -j DROP
-A PREROUTING -p tcp -m tcp --tcp-flags FIN,SYN FIN,SYN -m comment --comment "Block Packets With Bogus TCP Flags" -j DROP
-A PREROUTING -p tcp -m tcp --tcp-flags SYN,RST SYN,RST -m comment --comment "Block Packets With Bogus TCP Flags" -j DROP
-A PREROUTING -p tcp -m tcp --tcp-flags FIN,RST FIN,RST -m comment --comment "Block Packets With Bogus TCP Flags" -j DROP
-A PREROUTING -p tcp -m tcp --tcp-flags FIN,ACK FIN -m comment --comment "Block Packets With Bogus TCP Flags" -j DROP
-A PREROUTING -p tcp -m tcp --tcp-flags ACK,URG URG -m comment --comment "Block Packets With Bogus TCP Flags" -j DROP
-A PREROUTING -p tcp -m tcp --tcp-flags FIN,ACK FIN -m comment --comment "Block Packets With Bogus TCP Flags" -j DROP
-A PREROUTING -p tcp -m tcp --tcp-flags PSH,ACK PSH -m comment --comment "Block Packets With Bogus TCP Flags" -j DROP
-A PREROUTING -p tcp -m tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG FIN,SYN,RST,PSH,ACK,URG -m comment --comment "Block Packets With Bogus TCP Flags" -j DROP
-A PREROUTING -p tcp -m tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG NONE -m comment --comment "Block Packets With Bogus TCP Flags" -j DROP
-A PREROUTING -p tcp -m tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG FIN,PSH,URG -m comment --comment "Block Packets With Bogus TCP Flags" -j DROP
-A PREROUTING -p tcp -m tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG FIN,SYN,PSH,URG -m comment --comment "Block Packets With Bogus TCP Flags" -j DROP
-A PREROUTING -p tcp -m tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG FIN,SYN,RST,ACK,URG -m comment --comment "Block Packets With Bogus TCP Flags" -j DROP
-A PREROUTING -f -m comment --comment "Blocks fragmented packets" -j DROP
COMMIT

*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:LOGGING - [0:0]
-A INPUT -p tcp -m tcp --tcp-flags RST RST -m limit --limit 2/sec --limit-burst 2 -m comment --comment "Allow incoming TCP RST packets" -j ACCEPT
-A INPUT -p tcp -m tcp --tcp-flags RST RST -m comment --comment "Limit incoming TCP RST packets to mitigate TCP RST floods" -j LOGGING
-A INPUT -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK RST -m limit --limit 2/sec --limit-burst 2 -m comment --comment "Protection against port scanning" -j ACCEPT
-A INPUT -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK RST -m comment --comment "Protection against port scanning" -j LOGGING
-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -m comment --comment "Allow related connections" -j ACCEPT
-A INPUT -p tcp -m connlimit --connlimit-above 64 --connlimit-mask 32 --connlimit-saddr -m comment --comment "Rejects connections from hosts that have more than 64 established connections" -j REJECT --reject-with tcp-reset
-A INPUT -p tcp -m tcp --dport 22 -m conntrack --ctstate NEW -m recent --set --name DEFAULT --mask 255.255.255.255 --rsource -m comment --comment "record ssh connection"
-A INPUT -p tcp -m tcp --dport 22 -m conntrack --ctstate NEW -m recent --update --seconds 60 --hitcount 5 --name DEFAULT --mask 255.255.255.255 --rsource -m comment --comment "SSH brute-force protection" -j LOGGING
-A INPUT -p tcp -m conntrack --ctstate NEW -m limit --limit 32/sec --limit-burst 20 -m comment --comment "Allow the new TCP connections that a client can establish per second under limit" -j ACCEPT
-A INPUT -p tcp -m conntrack --ctstate NEW -m comment --comment "Limits the new TCP connections that a client can establish per second" -j LOGGING
-A INPUT -j LOGGING
-A LOGGING -m limit --limit 100/sec --limit-burst 20 -m comment --comment "logging dropped packets" -j LOG --log-prefix "Filter-Dropped: "
COMMIT
EOF
	cat > "${ROOT}/var/lib/ip6tables/rules-save" << EOF
*mangle
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A PREROUTING -m conntrack --ctstate INVALID -m comment --comment "Block Invalid Packets" -j DROP
-A PREROUTING -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -m comment --comment "Block New Packets That Are Not SYN" -j DROP
-A PREROUTING -p tcp -m conntrack --ctstate NEW -m tcpmss ! --mss 536:65535 -m comment --comment "Block Uncommon MSS Values" -j DROP
-A PREROUTING -p tcp -m tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG NONE -m comment --comment "Block Packets With Bogus TCP Flags" -j DROP
-A PREROUTING -p tcp -m tcp --tcp-flags FIN,SYN FIN,SYN -m comment --comment "Block Packets With Bogus TCP Flags" -j DROP
-A PREROUTING -p tcp -m tcp --tcp-flags SYN,RST SYN,RST -m comment --comment "Block Packets With Bogus TCP Flags" -j DROP
-A PREROUTING -p tcp -m tcp --tcp-flags FIN,RST FIN,RST -m comment --comment "Block Packets With Bogus TCP Flags" -j DROP
-A PREROUTING -p tcp -m tcp --tcp-flags FIN,ACK FIN -m comment --comment "Block Packets With Bogus TCP Flags" -j DROP
-A PREROUTING -p tcp -m tcp --tcp-flags ACK,URG URG -m comment --comment "Block Packets With Bogus TCP Flags" -j DROP
-A PREROUTING -p tcp -m tcp --tcp-flags FIN,ACK FIN -m comment --comment "Block Packets With Bogus TCP Flags" -j DROP
-A PREROUTING -p tcp -m tcp --tcp-flags PSH,ACK PSH -m comment --comment "Block Packets With Bogus TCP Flags" -j DROP
-A PREROUTING -p tcp -m tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG FIN,SYN,RST,PSH,ACK,URG -m comment --comment "Block Packets With Bogus TCP Flags" -j DROP
-A PREROUTING -p tcp -m tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG NONE -m comment --comment "Block Packets With Bogus TCP Flags" -j DROP
-A PREROUTING -p tcp -m tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG FIN,PSH,URG -m comment --comment "Block Packets With Bogus TCP Flags" -j DROP
-A PREROUTING -p tcp -m tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG FIN,SYN,PSH,URG -m comment --comment "Block Packets With Bogus TCP Flags" -j DROP
-A PREROUTING -p tcp -m tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG FIN,SYN,RST,ACK,URG -m comment --comment "Block Packets With Bogus TCP Flags" -j DROP
COMMIT

*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:LOGGING - [0:0]
-A INPUT -p tcp -m tcp --tcp-flags RST RST -m limit --limit 2/sec --limit-burst 2 -m comment --comment "Allow incoming TCP RST packets" -j ACCEPT
-A INPUT -p tcp -m tcp --tcp-flags RST RST -m comment --comment "Limit incoming TCP RST packets to mitigate TCP RST floods" -j LOGGING
-A INPUT -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK RST -m limit --limit 2/sec --limit-burst 2 -m comment --comment "Protection against port scanning" -j ACCEPT
-A INPUT -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK RST -m comment --comment "Protection against port scanning" -j LOGGING
-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -m comment --comment "Allow related connections" -j ACCEPT
-A INPUT -p tcp -m connlimit --connlimit-above 64 --connlimit-mask 128 --connlimit-saddr -m comment --comment "Rejects connections from hosts that have more than 64 established connections" -j REJECT --reject-with tcp-reset
-A INPUT -p tcp -m tcp --dport 22 -m conntrack --ctstate NEW -m recent --set --name DEFAULT --mask ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff --rsource -m comment --comment "record ssh connection"
-A INPUT -p tcp -m tcp --dport 22 -m conntrack --ctstate NEW -m recent --update --seconds 60 --hitcount 5 --name DEFAULT --mask ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff --rsource -m comment --comment "SSH brute-force protection" -j LOGGING
-A INPUT -p tcp -m conntrack --ctstate NEW -m limit --limit 32/sec --limit-burst 20 -m comment --comment "Allow the new TCP connections that a client can establish per second under limit" -j ACCEPT
-A INPUT -p tcp -m conntrack --ctstate NEW -m comment --comment "Limits the new TCP connections that a client can establish per second" -j LOGGING
-A INPUT -j LOGGING
-A LOGGING -m limit --limit 100/sec --limit-burst 20 -m comment --comment "logging dropped packets" -j LOG --log-prefix "Filter-Dropped: "
COMMIT
EOF

	if [[ ! -z "${ENABLESYSTEMD}" ]]; then
		mkdir --parents "${ROOT}/etc/systemd/network"
		cat > "${ROOT}/etc/systemd/network/50-dhcp.network" << EOF
[Match]
Name=e[nt]*
[Network]
DHCP=yes
EOF
		mkdir --parents "${ROOT}/etc/systemd/system/shutdown.target.wants" "${ROOT}/etc/systemd/system/basic.target.wants"
		sed --in-place --expression="s/-w\s//" "${ROOT}/lib/systemd/system/iptables-restore.service"
		sed --in-place --expression="s/-w\s//" "${ROOT}/lib/systemd/system/ip6tables-restore.service"
		ln --symbolic --force /lib/systemd/system/iptables-store.service  "${ROOT}/etc/systemd/system/shutdown.target.wants/iptables-store.service"
		ln --symbolic --force /lib/systemd/system/iptables-restore.service  "${ROOT}/etc/systemd/system/basic.target.wants/iptables-restore.service"
		ln --symbolic --force /lib/systemd/system/ip6tables-store.service "${ROOT}/etc/systemd/system/shutdown.target.wants/ip6tables-store.service"
		ln --symbolic --force /lib/systemd/system/ip6tables-restore.service "${ROOT}/etc/systemd/system/basic.target.wants/ip6tables-restore.service"

		mkdir --parents "${ROOT}/etc/systemd/system/multi-user.target.wants"
		ln --symbolic --force /lib/systemd/system/sshd.service "${ROOT}/etc/systemd/system/multi-user.target.wants/sshd.service"
	else
		sed --in-place --expression='s/^#rc_logger="NO"/rc_logger="YES"/' "${ROOT}/etc/rc.conf"

		for ifname in $(ls -l /sys/class/net/ | grep pci | sed 's/.*net\/\(.*\)/\1/'); do
			ln --symbolic --force net.lo "${ROOT}/etc/init.d/net.${ifname}"
			ln --symbolic --force "/etc/init.d/net.${ifname}" "${ROOT}/etc/runlevels/default/net.${ifname}"
		done
		ln --symbolic --force /etc/init.d/iptables  "${ROOT}/etc/runlevels/default/iptables"
		ln --symbolic --force /etc/init.d/ip6tables "${ROOT}/etc/runlevels/default/ip6tables"
		ln --symbolic --force /etc/init.d/sshd "${ROOT}/etc/runlevels/default/sshd"
	fi

    return 0
}

prepare-chroot() {
	LOGI "prepare chroot"

	cp --dereference --remove-destination --force /etc/resolv.conf "${ROOT}/etc/"

	mount --types proc /proc "${ROOT}/proc"

	mount --rbind /sys "${ROOT}/sys"
	mount --make-rslave "${ROOT}/sys"

	mount --rbind /dev "${ROOT}/dev"
	mount --make-rslave "${ROOT}/dev"

	# fix grub-mkconfig takes a long time
	mount --rbind /run "${ROOT}/run"
	mount --make-rslave "${ROOT}/run"

	test -L /dev/shm && rm /dev/shm && mkdir /dev/shm && mount --types tmpfs --options nosuid,nodev,noexec shm /dev/shm && chmod 1777 /dev/shm

	if [[ ! -z "${DEBUG}" ]]; then
		mkdir --parents "${ROOT}/usr/portage/packages"
		mkdir --parents "${ROOT}/usr/portage/distfiles"
		mount --bind "${ABSROOT}/resources/packages" "${ROOT}/usr/portage/packages"
		mount --bind "${ABSROOT}/resources/distfiles" "${ROOT}/usr/portage/distfiles"
	fi

	return 0
}

chroot-into-gentoo() {
	LOGI "chroot into gentoo"

	local cmdline=
	local opts=
	local profile="${PROFILE}"
	local pkgs="sys-apps/pciutils sys-kernel/genkernel-next sys-kernel/linux-firmware sys-kernel/gentoo-sources"
	local genopts=

	if [[ ! -z "${ENABLEDMCRYPT}" ]]; then
		cmdline="dolvm crypt_root=UUID=$(blkid --output=value --match-tag=UUID "${CRYPTDEV}")"
	elif [[ ! -z "${ENABLELVM}" ]]; then
		cmdline="dolvm"
	fi
	if [[ ! -z "${ENABLESYSTEMD}" ]]; then
		if [[ ! "${cmdline}" =~ init=/usr/lib/systemd/systemd ]]; then
			cmdline="${cmdline} init=/usr/lib/systemd/systemd"
		fi
		if [[ ! "${profile}" =~ /systemd ]]; then
			profile="${profile}/systemd"
		fi
	fi
	if [[ ! -z "${DEBUG}" ]]; then
		opts="--getbinpkg --buildpkg"
	fi

	if [[ ! -z "${ENABLEDMCRYPT}" ]]; then
		genopts="--lvm --luks"
	elif [[ ! -z "${ENABLELVM}" ]]; then
		genopts="--lvm"
	fi

	chroot "${ROOT}" /bin/bash << DOCHERE
eselect profile set "${profile}"
env-update && source /etc/profile

emerge --quiet --deep --newuse ${opts} @world && (\
	emerge --quiet ${opts} --autounmask-write sys-boot/grub net-firewall/iptables net-firewall/ipset app-admin/sudo ${pkgs} || \
	etc-update --quiet --automode -5 /etc/portage \
	) && emerge --quiet ${opts}               sys-boot/grub net-firewall/iptables net-firewall/ipset app-admin/sudo ${pkgs} && \
emerge --quiet --depclean || exit 1

test -e /etc/lvm/lvm.conf && sed --in-place --expression "s/use_lvmetad = 1/use_lvmetad = 0/" /etc/lvm/lvm.conf

if [[ -f /kernel.config ]]; then
	mv /kernel.config /usr/src/linux/.config
	if [[ "x" == "x${KERNEL}" ]]; then
		LOGI "compile kernel"
		pushd /usr/src/linux/
			make --quiet olddefconfig && make --quiet --jobs=$((CPUCOUNT * 2 + 1)) && make --quiet modules_install && make --quiet install
		popd

		LOGI "generate initramfs"
		genkernel --loglevel=0 ${genopts} --udev --virtio --install initramfs

		if [[ "x" != "x${DEBUG}" ]]; then
			md5=\$(md5sum /usr/src/linux/.config|cut --delimiter=' ' --fields=1)
			if [[ ! -e /kernel.\${md5}.tar.gz ]]; then
				LOGI "pack firmware"
				rm /kernel.*.tar.gz
				bash /pack.gentoo.kernel.sh
			fi
		fi
	fi
fi

echo "GRUB_CMDLINE_LINUX=\"${cmdline}\"" >> /etc/default/grub
echo "GRUB_DEVICE=UUID=$(blkid --output=value --match-tag=UUID "${ROOTDEV}")" >> /etc/default/grub
if [[ "x" != "x${ENABLEBIOS}" ]]; then
	grub-install --target=i386-pc "${DEV}"
fi
grub-install --target=x86_64-efi --efi-directory=/boot --removable
grub-mkconfig --output=/boot/grub/grub.cfg
DOCHERE

	if [[ 0 -ne $? ]]; then
		return $?
	fi

	ensure-sudoers
	dump-ipset-entities

	sed --in-place --expression="s/-w\s//" "${ROOT}/lib/systemd/system/iptables-restore.service"
	sed --in-place --expression="s/-w\s//" "${ROOT}/lib/systemd/system/ip6tables-restore.service"
	sed --in-place '/-A PREROUTING -f -m comment --comment "Blocks fragmented packets" -j DROP/i -A PREROUTING -m set --match-set ReservedNet src -m comment --comment "Block spoofed packets" -j DROP' "${ROOT}/var/lib/iptables/rules-save"
	sed --in-place '/-A PREROUTING -p tcp -m tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG FIN,SYN,RST,ACK,URG -m comment --comment "Block Packets With Bogus TCP Flags" -j DROP/a -A PREROUTING -s ::1/128 -i lo -m comment --comment "Allow loopback" -j ACCEPT' "${ROOT}/var/lib/ip6tables/rules-save"

	if [[ ! -z "${ENABLESYSTEMD}" ]]; then
		enable-systemd-services
	else
		enable-openrc-services
	fi

	return 0
}

chroot-into-gentoo-for-repair() {
	LOGI "chroot into gentoo for repair"

	chroot "${ROOT}" /bin/bash

	return $?
}

custom-gentoo () {
	return 0
}

prepare-stage3() {
	local path=
	local filename=
	local url=
	local stage3=
	if [[ -z "${STAGE3}" ]]; then
		for mirror in ${MIRRORS}; do
			url="${mirror%%/}/releases/${ARCH}/autobuilds/latest-stage3-${MARCH}.txt"
			path="$(curl --silent "${url}" | grep --invert-match --extended-regexp "^#" | cut --delimiter=" " --fields=1)"
			if [[ -z "${path}" ]]; then
				LOGW "query the latest-stage3-${ARCH} from ${mirror} failed"
				continue
			fi
			url="${mirror%%/}/releases/${ARCH}/autobuilds/${path}"
			filename="$(basename "${path}")"
			stage3="${ABSROOT}/resources/${filename}"

			if check-stage3 "${stage3}"; then
				STAGE3="${stage3}"
				break
			fi

			LOGD "downloading ${url}"
			curl --silent --location --output "${stage3}" "${url}" && curl --silent --location --output "${stage3}.DIGESTS" "${url}.DIGESTS"

			if check-stage3 "${stage3}"; then
				STAGE3="${stage3}"
				break
			else
				LOGW "check sum failed"
				rm --force "${stage3}" "${stage3}.DIGESTS"
			fi
		done
	fi
	if [[ -e "${STAGE3}" ]]; then
		return 0
	else
		return 1
	fi
}

check-stage3() {
	local chk=0
	local filename="$(basename "${1}")"

	if [[ -e "${1}" && -e "${1}.DIGESTS" ]]; then
		pushd "$(dirname "${1}")"
			chk="$(shasum --check "${filename}.DIGESTS" 2>/dev/null | grep "${filename}:" | grep --count "OK")"
		popd
	fi

	if [[ 1 -eq "${chk}" ]]; then
		return 0
	else
		return 1
	fi
}

prepare-portage() {
	local portage="${ABSROOT}/resources/portage-latest.tar.xz"
	local url=
	if [[ -z "${PORTAGE}" ]]; then
		for mirror in ${MIRRORS}; do
			url="${mirror%%/}/snapshots/portage-latest.tar.xz"

			if check-portage "${portage}"; then
				PORTAGE="${portage}"
				break
			fi

			LOGD "downloading ${url}"
			curl --silent --location --output "${portage}" "${url}" && \
				curl --silent --location --output "${portage}.md5sum" "${url}.md5sum"

			if check-portage "${portage}"; then
				PORTAGE="${portage}"
				break
			else
				LOGW "check sum failed"
				rm --force "${portage}" "${portage}.md5sum"
			fi
		done
	fi
	if [[ -e "${PORTAGE}" ]]; then
		return 0
	else
		return 1
	fi
}

check-portage() {
	local ret=1
	local filename="$(basename "${1}")"

	if [[ -e "${1}" && -e "${1}.md5sum" ]]; then
		pushd "$(dirname "${1}")"
			if md5sum --check "${filename}.md5sum" > /dev/null; then
				ret=0
			else
				ret=1
			fi
		popd
	fi

	return "${ret}"
}

getmemsize() {
	local ret=
	local size=2
	local KB=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
	if [[ 262144 -ge ${KB} ]]; then
		ret=256
	elif [[ 524288 -ge ${KB} ]]; then
		ret=512
	elif [[ 1048576 -ge ${KB} ]]; then
		ret=1024
	else
		until [[ $((size * 1048576)) -ge ${KB} ]]
		do
			size=$((size + 1))
		done
		ret=$((1024 * size))
	fi
	echo ${ret}
}

make-partitions() {
	LOGI "make partitions"

	local n=0
	local offset=1

	adjust-vgname

	if [[ ! -z "${ENABLEDMCRYPT}" ]]; then
		lvscan
		test -e "/dev/${VGNAME}/${SWAPLABEL}" && lvremove --force "/dev/${VGNAME}/${SWAPLABEL}"
		test -e "/dev/${VGNAME}/${ROOTLABEL}" && lvremove --force "/dev/${VGNAME}/${ROOTLABEL}"
		test -e "/dev/${VGNAME}" && vgremove --force "${VGNAME}"
	fi

	if ! parted --script --align=opt "${DEV}" "mklabel ${DEVTAB}"; then
		LOGE "parted ${DEV} mklabel ${DEVTAB} failed"
		return 1
	fi

	if test ! -z "${ENABLEBIOS}" && ! parted --script --align=opt "${DEV}" "mkpart primary ${offset} $((offset + 2))"; then
		LOGE "mkpart bios failed"
		return 1
	elif [[ ! -z "${ENABLEBIOS}" ]]; then
		offset=$((offset + 2))
		n=$((n + 1))
		if test "gpt" == "${DEVTAB}" && ! parted --script --align=opt "${DEV}" "set ${n} bios_grub on"; then
			LOGE "set part ${n} GRUB BIOS failed"
			return 1
		fi
	fi

	if ! parted --script --align=opt "${DEV}" "mkpart primary fat32 ${offset} $((offset + 64))"; then
		LOGE "mkpart boot failed"
		return 1
	else
		offset=$((offset + 64))
		n=$((n + 1))
		BOOTDEV="$(getpart "${DEV}" ${n})"
		if ! parted --script --align=opt "${DEV}" "set ${n} boot on"; then
			LOGE "set boot flag failed"
			return 1
		fi
	fi

	if [[ ! -z "${ENABLEDMCRYPT}" ]]; then
		if ! parted --script --align=opt "${DEV}" "mkpart primary ${offset} 100%"; then
			LOGE "mkpart luks failed"
			return 1
		fi
		n=$((n + 1))
		CRYPTDEV="$(getpart "${DEV}" ${n})"
	else
		if ! parted --script --align=opt "${DEV}" "mkpart primary linux-swap ${offset} $((offset + MEMSIZE))"; then
			LOGE "mkpart swap failed"
			return 1
		else
			n=$((n + 1))
			offset=$((offset + MEMSIZE))
			SWAPDEV="$(getpart "${DEV}" "${n}")"
		fi
		if ! parted --script --align=opt "${DEV}" "mkpart primary ${offset} 100%"; then
			LOGE "mkpart root failed"
			return 1
		fi
		n=$((n + 1))
		ROOTDEV="$(getpart "${DEV}" "${n}")"
	fi

	adjust-vgname

	if ! partprobe "${DEV}"; then
		LOGE "partprobe ${DEV} failed"
		return 1
	else
		return 0
	fi
}

# join dev and partition number
# /dev/sda 1 -> /dev/sda1
# /dev/nbd0 1 -> /dev/nbd0p1
# /dev/mmcblk0 1 -> /dev/mmcblk0p1
getpart() {
	if [[ "${1}" =~ ^/dev/(nbd|mmcblk)[0-9]+$ ]]; then
		echo "${1}p${2}"
	else
		echo "${1}${2}"
	fi
}

getfsdev() {
	local n=
	if [[ ! -z "${RUNNINGDEV}" ]]; then
		n="$(echo "${1}" | grep --only-matching --perl-regexp '\d+$')"
		if [[ ! -z "${n}" ]]; then
			getpart "${RUNNINGDEV}" "${n}"
		else
			echo "${1}"
		fi
	else
		echo "${1}"
	fi
}

mkrootfs() {
	if [[ "${ROOTFS}" == ext* ]]; then
		mkfs.${ROOTFS} -F -L "${ROOTLABEL}" "${1}"
	elif [[ ${ROOTFS} == "f2fs" ]]; then
		mkfs.${ROOTFS} -f -l "${ROOTLABEL}" "${1}"
	else
		return 1
	fi
	return $?
}

getcpucount() {
	grep --count processor /proc/cpuinfo
}

config-sshd() {
cat << EOF | mergeConfigFile "${ROOT}/etc/ssh/sshd_config"
PermitRootLogin no
ChallengeResponseAuthentication no
PasswordAuthentication no
PermitEmptyPasswords no
UsePAM no
AuthenticationMethods publickey
PubkeyAuthentication yes
ClientAliveInterval 300
ClientAliveCountMax 0
IgnoreRhosts yes
HostbasedAuthentication no
HostKey /etc/ssh/ssh_host_ed25519_key
KexAlgorithms curve25519-sha256@libssh.org,ecdh-sha2-nistp521,ecdh-sha2-nistp384,ecdh-sha2-nistp256,diffie-hellman-group-exchange-sha256
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256,umac-128@openssh.com
LogLevel VERBOSE
Subsystem sftp /usr/lib64/misc/sftp-server
Protocol 2
X11Forwarding no
MaxStartups 2
EOF
	return 0
}

mergeConfigFile() {
	local path=
	local name=
	local value=
	path="${1}"
	while read -r item
	do
		name=$(echo "${item}" | cut --delimiter=" " --fields=1)
		value="${item//\//\\\/}"
		sed --in-place --expression="s/^\(${name}\s.*\)/#\1/" "${path}"
		sed --in-place "0,/^#${name}\s.*/s//${value}/" "${path}"
		if [[ 0 -eq $(grep --extended-regexp --count "^${name}\s" "${path}") ]]; then
			echo "# added by script" >> "${path}"
			echo "${item}" >> "${path}"
		fi
	done
	return 0
}

x-chpasswd() {
	local usr="${1}"
	local pass="${2}"

	sed --in-place "/^${usr}:/d" "${ROOT}/etc/shadow"

	if [[ ! -z "${pass}" ]]; then
		echo "${usr}:$(openssl passwd -1 "${pass}"):$(($(date --utc +%s) / 86400)):0:99999:7:::" >> "${ROOT}/etc/shadow"
	else
		echo "${usr}::$(($(date --utc +%s) / 86400)):0:99999:7:::" >> "${ROOT}/etc/shadow"
	fi

	return 0
}

x-useradd() {
	local usr="${1}"
	local grps="${2}"
	local uid=1000
	local line=
	local grp=
	local gid=
	local sep=
	local added=

	until [[ 0 -eq $(cut --delimiter=: --fields=3 < "${ROOT}/etc/passwd" | grep --count ${uid}) ]]; do
		uid=$((uid + 1))
	done

	for grp in ${grps//,/ }; do
		line=$(grep "^${grp}:" "${ROOT}/etc/group")
		gid=$(echo "${line}" | cut --delimiter=: --fields=3)
		if [[ -z "${gid}" ]]; then
			continue
		fi

		if [[ -z "${added}" ]]; then
			echo "${usr}:x:${uid}:${gid}:daily user:/home/${usr}:/bin/bash" >> "${ROOT}/etc/passwd"
			echo "${usr}:*:$(($(date --utc +%s) / 86400)):0:99999:7:::" >> "${ROOT}/etc/shadow"
			mkdir --parents "${ROOT}/home/${usr}/.ssh"
			touch "${ROOT}/home/${usr}/.ssh/authorized_keys"
			chmod 0600 "${ROOT}/home/${usr}/.ssh/authorized_keys"
			chmod o-w "${ROOT}/home/${usr}"
			chmod g-w "${ROOT}/home/${usr}"
			chown --recursive ${uid}:${gid} "${ROOT}/home/${usr}"
			added=true
		fi

		if [[ "${line}" == *: ]]; then
			sep=""
		else
			sep=","
		fi
		sed --in-place --expression "s/${line}/${line}${sep}${usr}/" "${ROOT}/etc/group"

		line=$(grep "^${grp}:" "${ROOT}/etc/gshadow")
		if [[ "${line}" == *: ]]; then
			sep=""
		else
			sep=","
		fi
		sed --in-place --expression "s/${line}/${line}${sep}${usr}/" "${ROOT}/etc/gshadow"
	done

	if [[ -z "${added}" ]]; then
		return 1
	fi
	return 0
}

x-groupadd() {
	local name isSystem gid
	name=${1}
	isSystem=${2}

	if [[ 0 -lt $(grep --count "^${name}:" "${ROOT}/etc/group") ]]; then
		return 0
	fi

	if [[ ! -z "${isSystem}" ]]; then
		gid=999
		until [[ 0 -eq $(grep --count ":${gid}:" "${ROOT}/etc/group") ]]; do
			gid=$((gid - 1))
		done
	else
		gid=1000
		until [[ 0 -eq $(grep --count ":${gid}:" "${ROOT}/etc/group") ]]; do
			gid=$((gid + 1))
		done
	fi

	echo "${name}:x:${gid}:" >> "${ROOT}/etc/group"
	echo "${name}:!::"       >> "${ROOT}/etc/gshadow"

	return 0
}

x-append-user-to-groups() {
	local usr grps line sep
	grps=${1}
	usr=${2}

	for grp in ${grps//,/ }; do
		for path in "${ROOT}/etc/group" "${ROOT}/etc/gshadow"; do
			line=$(grep "^${grp}:" "${path}")
			if [[ -z "${line}" ]]; then
				continue
			elif [[ 0 -lt $(cut --delimiter=: --fields=4 <<< "${line}" | grep --count "${usr}") ]]; then
				continue
			fi

			if [[ "${line}" == *: ]]; then
				sep=""
			else
				sep=","
			fi

			sed --in-place --expression "s/${line}/${line}${sep}${usr}/" "${path}"
		done
	done
}

ensure-sudoers() {
	LOGI "ensure /etc/sudoers"
	chmod u+w "${ROOT}/etc/sudoers"
	sed --in-place --expression "s/# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/" "${ROOT}/etc/sudoers"
	if [[ 0 -eq $(grep --extended-regexp --count "^%wheel\sALL=\(ALL\)\sNOPASSWD:\sALL$" "${ROOT}/etc/sudoers") ]]; then
		echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> "${ROOT}/etc/sudoers"
	fi
	chmod u-w "${ROOT}/etc/sudoers"
	return 0
}

dump-ipset-entities() {
	mkdir --parents "${ROOT}/var/lib/ipset"

	# https://www.iana.org/assignments/iana-ipv4-special-registry/iana-ipv4-special-registry.xhtml
	# https://www.iana.org/assignments/iana-ipv6-special-registry/iana-ipv6-special-registry.xhtml
	cat > "${ROOT}/var/lib/ipset/rules-save" << EOF
create ReservedNet hash:net family inet hashsize 1024 maxelem 65536
add ReservedNet 0.0.0.0/8
add ReservedNet 10.0.0.0/8
add ReservedNet 100.64.0.0/10
add ReservedNet 127.0.0.0/8
add ReservedNet 169.254.0.0/16
add ReservedNet 172.16.0.0/12
add ReservedNet 192.0.0.0/24
add ReservedNet 192.0.0.0/29
add ReservedNet 192.0.0.8/32
add ReservedNet 192.0.0.9/32
add ReservedNet 192.0.0.10/32
add ReservedNet 192.0.0.170/32
add ReservedNet 192.0.2.0/24
add ReservedNet 192.31.196.0/24
add ReservedNet 192.52.193.0/24
add ReservedNet 192.88.99.0/24
add ReservedNet 192.168.0.0/16
add ReservedNet 192.175.48.0/24
add ReservedNet 198.18.0.0/15
add ReservedNet 198.51.100.0/24
add ReservedNet 203.0.113.0/24
add ReservedNet 240.0.0.0/4
add ReservedNet 255.255.255.255/32
create ReservedNet6 hash:net family inet6 hashsize 1024 maxelem 65536
add ReservedNet6 ::1/128
add ReservedNet6 ::/128
add ReservedNet6 ::ffff:0:0/96
add ReservedNet6 64:ff9b::/96
add ReservedNet6 64:ff9b:1::/48
add ReservedNet6 100::/64
add ReservedNet6 2001::/23
add ReservedNet6 2001::/32
add ReservedNet6 2001:1::1/128
add ReservedNet6 2001:1::2/128
add ReservedNet6 2001:2::/48
add ReservedNet6 2001:3::/32
add ReservedNet6 2001:4:112::/48
add ReservedNet6 2001:5::/32
add ReservedNet6 2001:10::/28
add ReservedNet6 2001:20::/28
add ReservedNet6 2001:db8::/32
add ReservedNet6 2002::/16
add ReservedNet6 2620:4f:8000::/48
add ReservedNet6 fc00::/7
add ReservedNet6 fe80::/10
EOF
}

enable-systemd-services() {
	if [[ ! -e "${ROOT}/lib/systemd/system/ipset-store.service" ]]; then
		cat > "${ROOT}/lib/systemd/system/ipset-store.service" << EOF
[Unit]
Description=Store ipset
Before=iptables-store.service ip6tables-store.service
DefaultDependencies=No

[Service]
Type=oneshot
ExecStart=/bin/sh -c "/usr/sbin/ipset save > /var/lib/ipset/rules-save"

[Install]
WantedBy=shutdown.target
EOF
	fi
	if [[ ! -e "${ROOT}/lib/systemd/system/ipset-restore.service" ]]; then
		cat > "${ROOT}/lib/systemd/system/ipset-restore.service" << EOF
[Unit]
Description=Restore ipset
Before=iptables-restore.service ip6tables-restore.service
DefaultDependencies=No

[Service]
Type=oneshot
ExecStart=/bin/sh -c "/usr/sbin/ipset restore < /var/lib/ipset/rules-save"

[Install]
WantedBy=basic.target
EOF
	fi

	ln --no-dereference --symbolic --force /run/systemd/resolve/resolv.conf "${ROOT}/etc/resolv.conf"

	chroot "${ROOT}" /bin/bash << EOF
systemctl enable systemd-resolved.service
systemctl enable ipset-store.service
systemctl enable ipset-restore.service
EOF

	return 0
}

enable-openrc-services() {
	ln --symbolic --force /etc/init.d/ipset "${ROOT}/etc/runlevels/default/ipset"
	return 0
}

main() {
	argparse "${@}"

	if [[ 0 -ne ${UID} ]]; then
		LOGE "root privilege required"
	elif ! check-dev "${DEV}"; then
		LOGE "check device ${DEV} failed"
	elif ! check-platform "${PLATFORM}"; then
		LOGE "check platform ${PLATFORM} failed"
	elif ! check-platform-arguments; then
		LOGE "check platform ${PLATFORM} arguments failed"
	elif ! init-platform; then
		LOGE "init platform ${PLATFORM} failed"
	elif ! check-runtime; then
		LOGE "check runtime failed"
	elif test "install" == "${MODE}" && ! install; then
		LOGE "install failed"
	elif test "repair" == "${MODE}" && ! repair; then
		LOGE "repair failed"
	elif [[ "repair" != "${MODE}" && "install" != "${MODE}" ]]; then
		LOGW "What do you mean? ${MODE}"
	else
		LOGI "enjoy your gentoo, good bye."
	fi
}

main "${@}"
