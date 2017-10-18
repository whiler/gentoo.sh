#!/bin/bash

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

