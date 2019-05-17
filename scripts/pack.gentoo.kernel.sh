#!/bin/bash
# build kernel and initramfs for reusing
#

JOBS=$(($(grep --count processor /proc/cpuinfo) * 2 + 1))
md5=
tmp=$(mktemp --directory)
name=default

pushd /usr/src/linux
	rm --force linux-*-gentoo-*.tar.bz2
	md5="$(md5sum .config | cut --delimiter=" " --fields=1)"
	make --quiet --jobs=${JOBS}
	make --quiet --jobs=${JOBS} modules
	make --quiet tarbz2-pkg
	tar -xjf linux-*-gentoo-*.tar.bz2 -C "${tmp}"
	rm linux-*-gentoo-*.tar.bz2
popd

rm --force /boot/initramfs-${name}-*-gentoo
genkernel --loglevel=0 --lvm --luks --udev --virtio --install --kernname="${name}" initramfs
mv /boot/initramfs-${name}-*-gentoo "${tmp}/boot"
origin="$(ls ${tmp}/boot/initramfs-${name}-*-gentoo)"
mv ${origin} ${origin/${name}/genkernel}

tar -czf /kernel.${md5}.tar.gz  -C "${tmp}" .

rm --recursive --force "${tmp}"
