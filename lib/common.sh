#!/bin/bash
# only need shell built-in commands

_DT_FORMAT="+[%Y-%m-%d %H:%M:%S %Z]"

debug () {
	echo -e "$(date "${_DT_FORMAT}")" "[DEBUG]" "${@}"
}

info () {
	echo -e "$(date "${_DT_FORMAT}")" "\033[32m[INFO]\033[0m" "${@}"
}

warn () {
	echo -e "$(date "${_DT_FORMAT}")" "\033[33m[WARN]\033[0m" "${@}"
}

error () {
	echo -e "$(date "${_DT_FORMAT}")" "\033[31m[ERROR]\033[0m" "${@}"
	exit 1
}

red() {
	echo -e "\033[31m${@}\033[0m"
}

yellow() {
	echo -e "\033[33m${@}\033[0m"
}

green() {
	echo -e "\033[32m${@}\033[0m"
}
