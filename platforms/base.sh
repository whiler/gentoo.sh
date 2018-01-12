#!/bin/bash

source "${SCRIPT}/lib/log.sh"

init-memsize() {
	local mem="$(awk '/^MemTotal:/{print $2}' "/proc/meminfo")"
	if [[ 262144 -ge "${mem}" ]]; then
		MEMSIZE=256
	elif [[ 524288 -ge "${mem}" ]]; then
		MEMSIZE=512
	elif [[ 1048576 -ge "${mem}" ]]; then
		MEMSIZE=1024
	else
		local size=2
		until [[ $((size * 1048576)) -ge "${mem}" ]]
		do
			size=$((size + 1))
		done
		MEMSIZE=$((1024 * size))
	fi
}

init-cpucount() {
	CPUCOUNT="$(grep -c processor "/proc/cpuinfo")"
	return 0
}

check-platform-arguments() {
	return 0
}

init-platform() {
	init-memsize
	init-cpucount
	return 0
}
