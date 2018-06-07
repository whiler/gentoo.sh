#!/bin/bash

REPO="raspberrypi/firmware"
TAG="$(curl --silent "https://api.github.com/repos/${REPO}/tags" | grep "name" | head --lines=1 | cut --delimiter=\" --fields=4)"
if [[ ! -z "${TAG}" ]]; then
	echo "downloading https://github.com/${REPO}/archive/${TAG}.tar.gz"
	curl --silent --location --output "pi.kernel.${TAG}.tar.gz" "https://github.com/${REPO}/archive/${TAG}.tar.gz"
fi
