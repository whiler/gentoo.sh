#!/bin/bash

source "${SCRIPT}/lib/log.sh"

REQUIRED="${REQUIRED} cryptsetup"
ENABLEDMCRYPT=Y
ENABLESWAP=Y
ENABLESYSTEMD=Y

check-platform-arguments() {
	local ret=0
	if [[ -z "${DMCRYPTKEY}" ]]; then
		LOGW "dmcrypt-key is required"
		ret=1
	elif [[ ! -f "${DMCRYPTKEY}" ]]; then
		LOGW "dmcrypt-key ${DMCRYPTKEY} No such file"
		ret=1
	elif [[ -z "${USRNAME}" ]]; then
		LOGW "username is required"
		ret=1
	fi
	return ${ret}
}

init-platform() {
	modprobe {dm-mod,dm-crypt,aes,sha256,cbc}
	return $?
}

custom-gentoo () {
	LOGI "custom gentoo"
	
	local password=
	password="$(tr --delete --complement A-Za-z0-9_ < /dev/urandom | head --bytes=64 | xargs)"

	chroot "${ROOT}" /bin/bash << DOCHERE
emerge --quiet --getbinpkg app-admin/sudo

useradd --create-home --groups users,wheel --no-user-group --comment "daily user" ${USRNAME}
cat << EOF | passwd ${USRNAME}
${password}
${password}
EOF

mkdir --parents /home/${USRNAME}/.ssh
mv /root/.ssh/authorized_keys /home/${USRNAME}/.ssh/authorized_keys
chmod 0600 /home/${USRNAME}/.ssh/authorized_keys
chown --recursive ${USRNAME}:users /home/${USRNAME}/.ssh

chmod u+w /etc/sudoers
sed --in-place --expression "s/# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/" /etc/sudoers
if [[ 0 -eq \$(grep --extended-regexp --count "^%wheel\\sALL=\\(ALL\\)\\sNOPASSWD:\\sALL$" /etc/sudoers) ]]; then
	echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
fi
chmod u-w /etc/sudoers
DOCHERE

	return $?
}
