#!/bin/bash

source "${SCRIPT}/lib/common.sh"

init-memsize() {
	local mem="$(awk '/^MemTotal:/{print $2}' "/proc/meminfo")"
	if [[ 262144 -ge "${mem}" ]]; then
		MEMSIZE="256M"
	elif [[ 524288 -ge "${mem}" ]]; then
		MEMSIZE="512M"
	elif [[ 1048576 -ge "${mem}" ]]; then
		MEMSIZE="1G"
	else
		local size=2
		until [[ $((size * 1048576)) -ge "${mem}" ]]
		do
			size=$((size + 1))
		done
		MEMSIZE="${size}G"
	fi
}

init-cpucount() {
	CPUCOUNT="$(grep -c processor "/proc/cpuinfo")"
	return 0
}

init-platform() {
	init-memsize
	init-cpucount
	return 0
}

check-platform() {
	if [[ -z "${LUKS}" ]]; then
		error "argument luks required for platform generic"
	fi

	return 0
}
