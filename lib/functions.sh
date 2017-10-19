#!/bin/bash

source "${SCRIPT}/lib/common.sh"

# {{{ check-runtime
check-runtime() {
	local ret=0

	for cmd in ${REQUIRED[@]}
	do
		if ! which "${cmd}" > /dev/null; then
			red "Error! command '${cmd}' not found"
			ret=1
		fi
	done

	for cmd in ${OPTIONAL[@]}
	do
		if ! which "${cmd}" > /dev/null; then
			yellow "Warning! command '${cmd}' not found"
		fi
	done

	return "${ret}"
}
# }}}

prepare-resource() {
    return 0
}

prepare-disk() {
    return 0
}

extract-resource() {
    return 0
}

config-gentoo() {
    return 0
}

chroot-into-gentoo() {
    return 0
}

clean() {
    return 0
}

