#!/bin/bash

REQUIRED="${REQUIRED} cryptsetup"
ENABLEDMCRYPT=Y
ENABLESWAP=Y
ENABLESYSTEMD=Y

check-platform-arguments() {
	local ret=0
	if [[ -z "${DMCRYPTKEY}" ]]; then
		LOGW "dmcrypt-key is required"
		ret=1
	elif [[ ! -f "${DMCRYPTKEY}" ]]; then
		LOGW "dmcrypt-key ${DMCRYPTKEY} No such file"
		ret=1
	fi
	return ${ret}
}

init-platform() {
	modprobe {dm-mod,dm-crypt,aes,sha256,cbc}
	return $?
}

custom-gentoo () {
	LOGI "custom gentoo"

	echo "net-firewall/ipset -modules" >> "${ROOT}/etc/portage/package.use/ipset"
	mkdir --parents "${ROOT}/var/lib/ipset"
	# https://www.iana.org/assignments/iana-ipv4-special-registry/iana-ipv4-special-registry.xhtml
	# https://www.iana.org/assignments/iana-ipv6-special-registry/iana-ipv6-special-registry.xhtml
	cat > "${ROOT}/var/lib/ipset/rules-save" << EOF
create ReservedNet hash:net family inet hashsize 1024 maxelem 65536
add ReservedNet 0.0.0.0/8
add ReservedNet 10.0.0.0/8
add ReservedNet 100.64.0.0/10
add ReservedNet 127.0.0.0/8
add ReservedNet 169.254.0.0/16
add ReservedNet 172.16.0.0/12
add ReservedNet 192.0.0.0/24
add ReservedNet 192.0.0.0/29
add ReservedNet 192.0.0.8/32
add ReservedNet 192.0.0.9/32
add ReservedNet 192.0.0.10/32
add ReservedNet 192.0.0.170/32
add ReservedNet 192.0.2.0/24
add ReservedNet 192.31.196.0/24
add ReservedNet 192.52.193.0/24
add ReservedNet 192.88.99.0/24
add ReservedNet 192.168.0.0/16
add ReservedNet 192.175.48.0/24
add ReservedNet 198.18.0.0/15
add ReservedNet 198.51.100.0/24
add ReservedNet 203.0.113.0/24
add ReservedNet 240.0.0.0/4
add ReservedNet 255.255.255.255/32
create ReservedNet6 hash:net family inet6 hashsize 1024 maxelem 65536
add ReservedNet6 ::1/128
add ReservedNet6 ::/128
add ReservedNet6 ::ffff:0:0/96
add ReservedNet6 64:ff9b::/96
add ReservedNet6 64:ff9b:1::/48
add ReservedNet6 100::/64
add ReservedNet6 2001::/23
add ReservedNet6 2001::/32
add ReservedNet6 2001:1::1/128
add ReservedNet6 2001:1::2/128
add ReservedNet6 2001:2::/48
add ReservedNet6 2001:3::/32
add ReservedNet6 2001:4:112::/48
add ReservedNet6 2001:5::/32
add ReservedNet6 2001:10::/28
add ReservedNet6 2001:20::/28
add ReservedNet6 2001:db8::/32
add ReservedNet6 2002::/16
add ReservedNet6 2620:4f:8000::/48
add ReservedNet6 fc00::/7
add ReservedNet6 fe80::/10
EOF
	sed --in-place '/-A PREROUTING -f -m comment --comment "Blocks fragmented packets" -j DROP/i -A PREROUTING -s 127.0.0.0/8 -i lo -m comment --comment "Allow loopback" -j ACCEPT' "${ROOT}/var/lib/iptables/rules-save"
	sed --in-place '/-A PREROUTING -f -m comment --comment "Blocks fragmented packets" -j DROP/i -A PREROUTING -m set --match-set ReservedNet src -m comment --comment "Block spoofed packets" -j DROP' "${ROOT}/var/lib/iptables/rules-save"

	sed --in-place '/-A PREROUTING -p tcp -m tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG FIN,SYN,RST,ACK,URG -m comment --comment "Block Packets With Bogus TCP Flags" -j DROP/a -A PREROUTING -m set --match-set ReservedNet6 src -m comment --comment "Block spoofed packets" -j DROP' "${ROOT}/var/lib/ip6tables/rules-save"
	sed --in-place '/-A PREROUTING -p tcp -m tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG FIN,SYN,RST,ACK,URG -m comment --comment "Block Packets With Bogus TCP Flags" -j DROP/a -A PREROUTING -s ::1/128 -i lo -m comment --comment "Allow loopback" -j ACCEPT' "${ROOT}/var/lib/ip6tables/rules-save"
	if [[ ! -e "${ROOT}/lib/systemd/system/ipset-store.service" ]]; then
		cat > "${ROOT}/lib/systemd/system/ipset-store.service" << EOF
[Unit]
Description=Store ipset
Before=iptables-store.service ip6tables-store.service
DefaultDependencies=No

[Service]
Type=oneshot
ExecStart=/bin/sh -c "/usr/sbin/ipset save > /var/lib/ipset/rules-save"

[Install]
WantedBy=shutdown.target
EOF
	fi
	if [[ ! -e "${ROOT}/lib/systemd/system/ipset-restore.service" ]]; then
		cat > "${ROOT}/lib/systemd/system/ipset-restore.service" << EOF
[Unit]
Description=Restore ipset
Before=iptables-restore.service ip6tables-restore.service
DefaultDependencies=No

[Service]
Type=oneshot
ExecStart=/bin/sh -c "/usr/sbin/ipset restore < /var/lib/ipset/rules-save"

[Install]
WantedBy=basic.target
EOF
	fi

	cp --dereference --remove-destination --force /etc/resolv.conf "${ROOT}/etc/"
	chroot "${ROOT}" /bin/bash << DOCHERE
emerge --quiet net-firewall/ipset
systemctl enable ipset-store.service
systemctl enable ipset-restore.service
DOCHERE

	return 0
}
