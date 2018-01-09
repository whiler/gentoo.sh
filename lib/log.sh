#!/bin/bash
# only need shell built-in commands

_DT_FORMAT="+[%Y-%m-%d %H:%M:%S %Z]"

LOGD () {
	echo -e "$(date "${_DT_FORMAT}")" "[DEBUG]" "${@}"
}

LOGI () {
	echo -e "$(date "${_DT_FORMAT}")" "\033[32m[INFO]\033[0m" "${@}"
}

LOGW () {
	echo -e "$(date "${_DT_FORMAT}")" "\033[33m[WARN]\033[0m" "${@}"
}

LOGE () {
	echo -e "$(date "${_DT_FORMAT}")" "\033[31m[ERROR]\033[0m" "${@}"
	exit 1
}
