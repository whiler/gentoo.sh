#!/bin/bash

# join dev and partition number
# /dev/sda 1 -> /dev/sda1
# /dev/nbd0 1 -> /dev/nbd0p1
getdev() {
	if [[ "${1}" =~ ^/dev/nbd[0-9]+$ ]]; then
		echo "${1}p${2}"
	else
		echo "${1}${2}"
	fi
}

getcpucount() {
	grep --count processor /proc/cpuinfo
}

getmemsize() {
	local ret=
	local size=2
	local KB=
	KB=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
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

check-runtime() {
	local ret=0

	for cmd in ${REQUIRED[@]}
	do
		if ! which "${cmd}" > /dev/null; then
			LOGE "command '${cmd}' not found"
			ret=1
		fi
	done

	for cmd in ${OPTIONAL[@]}
	do
		if ! which "${cmd}" > /dev/null; then
			LOGW "command '${cmd}' not found"
		fi
	done

	return "${ret}"
}

check-stage3() {
	local stage3="${1}"
	local chk=0
	local filename=
	filename="$(basename "${stage3}")"

	if [[ -e "${stage3}" && -e "${stage3}.DIGESTS" ]]; then
		pushd "$(dirname "${stage3}")" > /dev/null
			chk="$(shasum --check "${filename}.DIGESTS" 2>/dev/null | grep "${filename}:" | grep --count "OK")"
		popd > /dev/null
	fi

	if [[ 1 -eq "${chk}" ]]; then
		return 0
	else
		return 1
	fi
}

prepare-stage3() {
	local path=
	local filename=
	local url=
	local stage3=
	if [[ -z "${STAGE3}" ]]; then
		for mirror in ${MIRRORS[@]}
		do
			url="${mirror%%/}/releases/${ARCH}/autobuilds/latest-stage3-${ARCH}.txt"
			path="$(curl --silent "${url}" | grep --invert-match --extended-regexp "^#" | cut --delimiter=" " --fields=1)"
			if [[ -z "${path}" ]]; then
				LOGW "query the latest-stage3-${ARCH} from ${mirror} failed"
				continue
			fi
			url="${mirror%%/}/releases/${ARCH}/autobuilds/${path}"
			filename="$(basename "${path}")"
			stage3="${SCRIPT}/resources/${filename}"

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

check-portage() {
	local portage="${1}"
	local ret=1
	local filename=
	filename="$(basename "${portage}")"

	if [[ -e "${portage}" && -e "${portage}.md5sum" ]]; then
		pushd "$(dirname "${portage}")" > /dev/null
			if md5sum --check "${filename}.md5sum" > /dev/null; then
				ret=0
			else
				ret=1
			fi
		popd > /dev/null
	fi

	return "${ret}"
}

prepare-portage() {
	local filename="portage-latest.tar.xz"
	local portage="${SCRIPT}/resources/${filename}"
	local url=
	if [[ -z "${PORTAGE}" ]]; then
		for mirror in ${MIRRORS[@]}
		do
			url="${mirror%%/}/snapshots/${filename}"

			if check-portage "${portage}"; then
				PORTAGE="${portage}"
				break
			fi

			LOGD "downloading ${url}"
			curl --silent --location --output "${portage}" "${url}" && curl --silent --location --output "${portage}.md5sum" "${url}.md5sum"

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


prepare-resource() {
	LOGI "prepare resource"
	local ret=0
	if ! prepare-stage3; then
		LOGW "prepare stage3 failed"
		ret=1
	elif ! prepare-portage; then
		LOGW "prepare portage failed"
		ret=1
	fi
    return "${ret}"
}

open-disk() {
	LOGI "open disk"
	local keypath=

	mkdir --parents "${ROOT}"

	if [[ -z "${ENABLEDMCRYPT}" && -z "${ENABLELVM}" ]]; then
		until [[ -e "$(getdev "${DEV}" 3)" ]]
		do
			sleep 0.3
		done
		if [[ ! -z "${ENABLESWAP}" ]]; then
			swapon "$(getdev "${DEV}" 3)"

			mount "$(getdev "${DEV}" 4)" "${ROOT}"
		else
			mount "$(getdev "${DEV}" 3)" "${ROOT}"
		fi
	else
		lvscan

		if [[ ! -z "${ENABLEDMCRYPT}" && ! -e "/dev/mapper/${DMCRYPTNAME}" ]]; then
			keypath="$(mktemp)"
			head -1 "${DMCRYPTKEY}" | tr --delete "\r\n" | tr --delete "\r" | tr --delete "\n" > "${keypath}"
			if ! cryptsetup luksOpen --key-file="${keypath}" "$(getdev "${DEV}" 3)" "${DMCRYPTNAME}"; then
				LOGE "luksOpen $(getdev "${DEV}" 3) failed"
			fi
			rm "${keypath}"
		fi

		until [[ -e "/dev/${VGNAME}" ]]
		do
			vgchange --activate=y "/dev/${VGNAME}"
			sleep 0.3
		done

		if [[ ! -z "${ENABLESWAP}" ]]; then
			until [[ -e "/dev/${VGNAME}/${SWAPLABEL}" ]]
			do
				lvchange --activate=y "/dev/${VGNAME}/${SWAPLABEL}"
				sleep 0.3
			done
			swapon "/dev/${VGNAME}/${SWAPLABEL}"
		fi

		until [[ -e "/dev/${VGNAME}/${ROOTLABEL}" ]]
		do
			lvchange --activate=y "/dev/${VGNAME}/${ROOTLABEL}"
			sleep 0.3
		done
		mount "/dev/${VGNAME}/${ROOTLABEL}" "${ROOT}"
	fi

	mkdir --parents "${ROOT}/boot"
	mount "$(getdev "${DEV}" 2)" "${ROOT}/boot"

	return 0
}

prepare-disk() {
	LOGI "prepare disk"
	local cmds=
	local linuxdev=
	local keypath=
	local memsize=
	local offset=
	memsize=$(getmemsize)
	offset=$((67 + memsize))

	if [[ -z "${ENABLEDMCRYPT}" && -z "${ENABLELVM}" ]]; then
		if [[ ! -z "${ENABLESWAP}" ]]; then
			cmds="$(cat <<EOF
unit mib
mkpart primary 1 3
name 1 grub
set 1 bios_grub on
mkpart ESI fat32 3 67
name 2 boot
set 2 boot on
mkpart primary linux-swap 67 ${offset}
name 3 swap
mkpart primary ext4 ${offset} 100%
name 4 root
quit
EOF
)"
		else
			cmds="$(cat <<EOF
unit mib
mkpart primary 1 3
name 1 grub
set 1 bios_grub on
mkpart ESI fat32 3 67
name 2 boot
set 2 boot on
mkpart primary ext4 67 100%
name 3 root
quit
EOF
)"
		fi
	else
		cmds="$(cat <<EOF
unit mib
mkpart primary 1 3
name 1 grub
set 1 bios_grub on
mkpart ESI fat32 3 67
name 2 boot
set 2 boot on
mkpart primary 67 100%
name 3 linux
quit
EOF
)"
		lvscan
		test -e "/dev/${VGNAME}/${SWAPLABEL}" && lvremove --force "/dev/${VGNAME}/${SWAPLABEL}"
		test -e "/dev/${VGNAME}/${ROOTLABEL}" && lvremove --force "/dev/${VGNAME}/${ROOTLABEL}"
		test -e "/dev/${VGNAME}" && vgremove --force "${VGNAME}"
	fi

	if ! parted --script --align=opt "${DEV}" "mktable gpt"; then
		LOGE "initialize ${DEV} failed"
	elif ! echo "${cmds}" | parted --align=opt "${DEV}"; then
		LOGE "partion  ${DEV} failed"
	elif ! partprobe "${DEV}"; then
		LOGE "partprobe ${DEV} failed"
	fi

	sleep 1.3

	until [[ -e "$(getdev "${DEV}" 2)" && -b "$(getdev "${DEV}" 2)" ]]
	do
		sleep 0.3
	done

	until [[ -e "$(getdev "${DEV}" 3)" && -b "$(getdev "${DEV}" 3)" ]]
	do
		sleep 0.3
	done

	if ! mkfs.vfat -F 32 -n BOOT "$(getdev "${DEV}" 2)"; then
		LOGE "format boot failed"
	else
		BOOTUUID="$(blkid -o value -s UUID "$(getdev "${DEV}" 2)")"
		if [[ -z "${ENABLEDMCRYPT}" && -z "${ENABLELVM}" ]]; then
			if [[ ! -z "${ENABLESWAP}" ]]; then
				if ! mkswap --force --label="${SWAPLABEL}" "$(getdev "${DEV}" 3)"; then
					LOGE "mkswap failed"
				elif ! mkfs.ext4 -F -L "${ROOTLABEL}" "$(getdev "${DEV}" 4)"; then
					LOGE "mkfs.ext4 failed"
				fi
				SWAPUUID="$(blkid -o value -s UUID "$(getdev "${DEV}" 3)")"
				ROOTUUID="$(blkid -o value -s UUID "$(getdev "${DEV}" 4)")"
			elif ! mkfs.ext4 -F -L "${ROOTLABEL}" "$(getdev "${DEV}" 3)"; then
				LOGE "mkfs.ext4 failed"
			else
				ROOTUUID="$(blkid -o value -s UUID "$(getdev "${DEV}" 3)")"
			fi
		else
			if [[ -z "${ENABLEDMCRYPT}" ]]; then
				linuxdev="$(getdev "${DEV}" 3)"
			else
				keypath="$(mktemp)"
				head -1 "${DMCRYPTKEY}" | tr --delete "\r\n" | tr --delete "\r" | tr --delete "\n" > "${keypath}"
				if ! cryptsetup luksFormat --batch-mode --key-file="${keypath}" "$(getdev "${DEV}" 3)"; then
					LOGE "luksFormat $(getdev "${DEV}" 3) failed"
				elif ! cryptsetup luksOpen --key-file="${keypath}" "$(getdev "${DEV}" 3)" "${DMCRYPTNAME}"; then
					LOGE "luksOpen $(getdev "${DEV}" 3) failed"
				fi
				rm "${keypath}"
				linuxdev="/dev/mapper/${DMCRYPTNAME}"
				CRYPTUUID="$(blkid -o value -s UUID "$(getdev "${DEV}" 3)")"
			fi
			if ! pvcreate --force --force --yes "${linuxdev}"; then
				LOGE "pvcreate on ${linuxdev} failed"
			elif ! vgcreate "${VGNAME}" "${linuxdev}"; then
				LOGE "vgcreate ${VGNAME} ${linuxdev} failed"
			fi
			if [[ ! -z "${ENABLESWAP}" ]]; then
				if ! lvcreate --yes --size="${memsize}M" --name="${SWAPLABEL}" "${VGNAME}"; then
					LOGE "lvcreate failed"
				elif ! mkswap --force --label="${SWAPLABEL}" "/dev/${VGNAME}/${SWAPLABEL}"; then
					LOGE "mkswap failed"
				else
					SWAPUUID="$(blkid -o value -s UUID "/dev/${VGNAME}/${SWAPLABEL}")"
				fi
			fi
			if ! lvcreate --yes --extents=100%FREE --name="${ROOTLABEL}" "${VGNAME}"; then
				LOGE "lvcreate failed"
			elif ! mkfs.ext4 -F -L "${ROOTLABEL}" "/dev/${VGNAME}/${ROOTLABEL}"; then
				LOGE "mkfs.ext4 failed"
			else
				ROOTUUID="$(blkid -o value -s UUID "/dev/${VGNAME}/${ROOTLABEL}")"
			fi
		fi
	fi

    return 0
}

extract-resource() {
	LOGI "extract resource"
	local ret=0

	if ! tar --extract --preserve-permissions --xattrs-include="*.*" --numeric-owner --file "${STAGE3}" --directory "${ROOT}"; then
		LOGW "extract stage3 failed"
		ret=1
	elif ! tar --extract --xz --file "${PORTAGE}" --directory "${ROOT}/usr"; then
		LOGW "extract portage failed"
		ret=1
	fi

    return "${ret}"
}

mergeConfigFile() {
	local path=
	local name=
	local value=
	path="${1}"
	while read item
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

config-ssh() {
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

config-gentoo() {
	LOGI "config gentoo"
	sed --in-place --expression="s/CFLAGS=\"-O2 -pipe\"/CFLAGS=\"-march=native -O2 -pipe\"/" "${ROOT}/etc/portage/make.conf"

	echo "MAKEOPTS=\"-j$(($(getcpucount) * 2 + 1))\"" >> "${ROOT}/etc/portage/make.conf"

	if [[ ! -z "${MIRRORS}" && "http://distfiles.gentoo.org/" != "${MIRRORS}" ]]; then
		echo "GENTOO_MIRRORS=\"${MIRRORS}\"" >> "${ROOT}/etc/portage/make.conf"
	fi

	mkdir --parents "${ROOT}/etc/portage/repos.conf"
	cp "${ROOT}/usr/share/portage/config/repos.conf" "${ROOT}/etc/portage/repos.conf/gentoo.conf"
	if [[ ! -z "${RSYNC}" && "rsync.gentoo.org" != "${RSYNC}" ]]; then
		sed --in-place --expression="s/rsync.gentoo.org/${RSYNC}/" "${ROOT}/etc/portage/repos.conf/gentoo.conf"
	fi

	echo "${TIMEZONE}" > "${ROOT}/etc/timezone"
	cp "${ROOT}/usr/share/zoneinfo/${TIMEZONE}" "${ROOT}/etc/localtime"

	echo "LINGUAS=\"en_US\"" >> "${ROOT}/etc/portage/make.conf"
	echo "LC_COLLATE=\"C\"" >>     "${ROOT}/etc/env.d/02locale"
	echo "LANG=\"en_US.UTF-8\"" >> "${ROOT}/etc/env.d/02locale"
	echo "en_US.UTF-8 UTF-8" >> "${ROOT}/etc/locale.gen"

	sed --in-place --expression="s/localhost/${HOSTNAME}/" "${ROOT}/etc/conf.d/hostname"
	cat > "${ROOT}/etc/hosts" <<EOF
127.0.0.1 ${HOSTNAME} localhost
::1 ${HOSTNAME} localhost
EOF

	sed --in-place --expression="s/root:\*:10770:0:::::/root::10770:0:::::/" "${ROOT}/etc/shadow"

	if [[ -z "${ENABLESWAP}" ]]; then
		cat > "${ROOT}/etc/fstab" <<EOF
UUID=${BOOTUUID} /boot auto noauto,noatime 1 2
UUID=${ROOTUUID} /     ext4 noatime        0 1
EOF
	else
		cat > "${ROOT}/etc/fstab" <<EOF
UUID=${BOOTUUID} /boot auto noauto,noatime 1 2
UUID=${SWAPUUID} none  swap sw             0 0
UUID=${ROOTUUID} /     ext4 noatime        0 1
EOF
	fi

	if [[ ! -z "${KERNEL}" && -f "${KERNEL}" ]]; then
		cp --dereference "${KERNEL}" "${ROOT}/kernel.tar.bz2"
	fi
	if [[ ! -z "${CONFIG}" && -f "${CONFIG}" ]]; then
		cp --dereference "${CONFIG}" "${ROOT}/kernel.config"
	fi

	echo "GRUB_PLATFORMS=\"efi-64 pc\"" >> "${ROOT}/etc/portage/make.conf"

	ln --symbolic --force /proc/self/mounts "${ROOT}/etc/mtab"

	mkdir --parents "${ROOT}/etc/portage/env"
	echo "MAKEOPTS=\"-j1\"" >> "${ROOT}/etc/portage/env/singleton"
	{
		echo "dev-libs/boost singleton";
		echo "dev-util/cmake singleton";
		echo "sys-block/thin-provisioning-tools singleton";
	} >> "${ROOT}/etc/portage/package.env"

	mkdir --parents "${ROOT}/etc/portage/package.use"
	if [[ ! -z "${ENABLEDMCRYPT}" ]]; then
		echo "sys-kernel/genkernel-next cryptsetup" >> "${ROOT}/etc/portage/package.use/genkernel-next"
	fi

	config-ssh

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

	test -L /dev/shm && rm /dev/shm && mkdir /dev/shm && mount --types tmpfs --options nosuid,nodev,noexec shm /dev/shm && chmod 1777 /dev/shm

	if [[ ! -z "${DEBUG}" ]]; then
		mkdir --parents "${ROOT}/usr/portage/packages"
		mkdir --parents "${ROOT}/usr/portage/distfiles"
		mount --bind "${SCRIPT}/resources/packages" "${ROOT}/usr/portage/packages"
		mount --bind "${SCRIPT}/resources/distfiles" "${ROOT}/usr/portage/distfiles"
	fi

	return 0
}

chroot-into-gentoo-for-repair() {
	LOGI "chroot into gentoo for repair"

	chroot "${ROOT}" /bin/bash

	return $?
}

config-iptables() {
	if [[ ! -z "${ENABLESYSTEMD}" ]]; then
		sed --in-place --expression="s/-w\s//" "${ROOT}/lib/systemd/system/iptables-restore.service"
		sed --in-place --expression="s/-w\s//" "${ROOT}/lib/systemd/system/ip6tables-restore.service"
	fi

	mkdir --parents "${ROOT}/var/lib/iptables"
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

	mkdir --parents "${ROOT}/var/lib/ip6tables"
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
	return 0
}

enable-service() {
	if [[ ! -z "${ENABLESYSTEMD}" ]]; then
		chroot "${ROOT}" /bin/bash <<EOF
env-update && source /etc/profile

systemd-machine-id-setup

echo "[Match]" >>      /etc/systemd/network/50-dhcp.network
echo "Name=e[nt]*" >>  /etc/systemd/network/50-dhcp.network
echo "[Network]" >>    /etc/systemd/network/50-dhcp.network
echo "DHCP=yes" >>     /etc/systemd/network/50-dhcp.network
systemctl enable systemd-networkd.service

ln --no-dereference --symbolic --force /run/systemd/resolve/resolv.conf /etc/resolv.conf
systemctl enable systemd-resolved.service

systemctl enable sshd.service
systemctl enable iptables-store.service
systemctl enable iptables-restore.service
systemctl enable ip6tables-store.service
systemctl enable ip6tables-restore.service
EOF
	else
		chroot "${ROOT}" /bin/bash <<EOF
env-update && source /etc/profile

for ifname in \$(ls -l /sys/class/net/ | grep pci | cut -d " " -f 9); do
	echo "config_\${ifname}=dhcp" >> /etc/conf.d/net
	ln --symbolic --force net.lo "/etc/init.d/net.\${ifname}"
	rc-update add "net.\${ifname}" boot
done

rc-update add sshd default

rc-update add iptables default
rc-update add ip6tables default
EOF
	fi

	return 0
}

add-dailyuser() {
	local password=
	local authorized=
	password="$(tr --delete --complement A-Za-z0-9_ < /dev/urandom | head --bytes=64 | xargs)"
	authorized="$(cat "${PUBLICKEY}")"

	chroot "${ROOT}" /bin/bash << DOCHERE
useradd --create-home --groups users,wheel --no-user-group --comment "daily user" ${USRNAME}
cat << EOF | passwd ${USRNAME}
${password}
${password}
EOF

mkdir --parents /home/${USRNAME}/.ssh
echo "${authorized}" > /home/${USRNAME}/.ssh/authorized_keys
chmod 0600 /home/${USRNAME}/.ssh/authorized_keys
chown --recursive ${USRNAME}:users /home/${USRNAME}/.ssh

chmod u+w /etc/sudoers
sed --in-place --expression "s/# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/" /etc/sudoers
if [[ 0 -eq \$(grep --extended-regexp --count "^%wheel\\sALL=\\(ALL\\)\\sNOPASSWD:\\sALL$" /etc/sudoers) ]]; then
	echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
fi
chmod u-w /etc/sudoers
DOCHERE
	return 0
}

chroot-into-gentoo() {
	LOGI "chroot into gentoo"

	local cmdline=
	local opts=
	local profile="${PROFILE}"
	local pkgs=
	local genopts=

	if [[ ! -z "${ENABLELVM}" && ! "${cmdline}" =~ dolvm ]]; then
		cmdline="${cmdline} dolvm"
	fi
	if [[ ! -z "${ENABLEDMCRYPT}" ]]; then
		if [[ ! "${cmdline}" =~ dolvm ]]; then
			cmdline="${cmdline} dolvm"
		fi
		if [[ ! "${cmdline}" =~ crypt_root= ]]; then
			cmdline="${cmdline} crypt_root=UUID=\"${CRYPTUUID}\""
		fi
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

	if [[ -z "${KERNEL}" ]]; then
		pkgs="sys-apps/pciutils sys-kernel/genkernel-next sys-kernel/linux-firmware sys-kernel/gentoo-sources"
	fi

	chroot "${ROOT}" /bin/bash << DOCHERE
eselect profile set "${profile}"
env-update && source /etc/profile

emerge --quiet --deep --newuse ${opts} @world
emerge --quiet ${opts} sys-boot/grub net-firewall/iptables app-admin/sudo ${pkgs}
emerge --quiet --depclean

if [[ -f /kernel.config ]]; then
	mv /kernel.config /usr/src/linux/.config
	pushd /usr/src/linux/
		make --quiet olddefconfig && make --quiet --jobs=$(($(getcpucount) * 2 + 1)) && make --quiet modules_install && make --quiet install
	popd

	genkernel --loglevel=0 ${genopts} --udev --virtio --install initramfs
elif [[ -f /kernel.tar.bz2 ]]; then
	tar --keep-directory-symlink --extract --bzip2 --file=/kernel.tar.bz2 --directory=/
	rm /kernel.tar.bz2
fi

echo "GRUB_CMDLINE_LINUX=\"${cmdline}\"" >> /etc/default/grub
echo "GRUB_DEVICE=UUID=\"${ROOTUUID}\"" >> /etc/default/grub
grub-install --target=i386-pc "${DEV}"
grub-install --target=x86_64-efi --efi-directory=/boot --removable
grub-mkconfig --output=/boot/grub/grub.cfg
DOCHERE

	add-dailyuser
	config-iptables
	enable-service

	return 0
}

clean() {
	LOGI "clean"

	local inSystemd=
	if [[ 0 -lt $(pgrep --full --count "/lib/systemd/systemd-timesyncd") ]]; then
		inSystemd=Y
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

		if [[ -z "${ENABLEDMCRYPT}" && -z "${ENABLELVM}" && ! -z "${ENABLESWAP}" ]]; then
			if [[ 0 -lt $(swapon --summary | grep --count "$(getdev "${DEV}" 3)") ]]; then
				swapoff "$(getdev "${DEV}" 3)"
			fi
		else
			if [[ ! -z "${ENABLESWAP}" && 0 -lt $(swapon --summary | grep --count "$(realpath "/dev/${VGNAME}/${SWAPLABEL}")") ]]; then
				swapoff "/dev/${VGNAME}/${SWAPLABEL}"
			fi
			test -e "/dev/${VGNAME}/${SWAPLABEL}" && lvchange --activate=n "/dev/${VGNAME}/${SWAPLABEL}"
			test -e "/dev/${VGNAME}/${ROOTLABEL}" && lvchange --activate=n "/dev/${VGNAME}/${ROOTLABEL}"
			test -e "/dev/${VGNAME}" && vgchange --activate=n "/dev/${VGNAME}"
			test -e "/dev/mapper/${DMCRYPTNAME}" && cryptsetup luksClose "/dev/mapper/${DMCRYPTNAME}"
		fi
	fi

	if [[ ! -z "${inSystemd}" ]]; then
		systemctl start systemd-timedated.service
		timedatectl set-ntp true
	fi

    return 0
}

custom-gentoo () {
	LOGI "custom gentoo"
	return 0
}
