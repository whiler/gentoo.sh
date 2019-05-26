#!/bin/bash

dest="${1}"
outdir="${dest:="."}"
repo="raspberrypi/firmware"
latestTag="$(curl --silent "https://api.github.com/repos/${repo}/tags" | grep "name" | head --lines=1 | cut --delimiter=\" --fields=4)"
if [[ ! -z "${latestTag}" ]]; then
	url="https://github.com/${repo}/archive/${latestTag}.tar.gz"
	filename="${outdir}/pi.kernel.${latestTag}.tar.gz"
	echo "fetching ${url} to ${filename}"
	until test -e "${filename}" && tar -tf "${filename}" > /dev/null 2>&1; do
		rm -f "${filename}"
		curl --silent --location --output "${filename}" ${url}
	done

	tmpdir="$(mktemp --directory)"
	tar -xzf "${filename}" -C "${tmpdir}"
	rm "${filename}"
	pushd "${tmpdir}/firmware-${latestTag}"
		rm  README.md
		rm -r documentation
		mv extra/* boot/
		rm -r extra
		mkdir -p lib
		mv modules lib
	popd
	tar -czf "${filename}" -C "${tmpdir}/firmware-${latestTag}" .
	rm -r "${tmpdir}"
else
	echo "get latest tag failed"
fi
