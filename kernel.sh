#!/bin/bash
# build kernel and initramfs for reusing
#

JOBS=$(($(grep --count processor /proc/cpuinfo) * 2 + 1))
md5=
tmp=/tmp/kernel
name=default
origin=

pushd /usr/src/linux
	rm --force linux-*-gentoo-*.tar.bz2
	md5="$(md5sum .config | cut --delimiter=" " --fields=1)"
	make --quiet --jobs=${JOBS}
	make --quiet --jobs=${JOBS} modules
	make --quiet tarbz2-pkg
	if [[ -e "${tmp}" ]]; then
		rm --recursive --force "${tmp}"
	fi
	mkdir --parents "${tmp}"
	tar -xjf linux-*-gentoo-*.tar.bz2 -C "${tmp}"
	rm linux-*-gentoo-*.tar.bz2
popd

rm --force /boot/initramfs-${name}-*-gentoo
genkernel --loglevel=0 --lvm --luks --udev --virtio --install --kernname="${name}" initramfs
mv /boot/initramfs-${name}-*-gentoo "${tmp}/boot"
origin="$(ls ${tmp}/boot/initramfs-${name}-*-gentoo)"
mv ${origin} ${origin/${name}/genkernel}

pushd "${tmp}"
	tar -cjf /kernel.${md5}.tar.bz2 .
popd

rm --recursive --force "${tmp}"
