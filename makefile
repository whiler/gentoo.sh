DEV ?= /dev/sdb
KCONFIG ?= $(CURDIR)/kernel.config
PUBKEY ?= $(HOME)/.ssh/id_rsa.pub
MODE ?= install
PLATFORM ?= base
DEBUG ?= true
DMCRYPTPASSWD ?= dMcr794
KERNEL ?=
MIRRORS ?= https://mirrors.tuna.tsinghua.edu.cn/gentoo
NODENAME ?=
MEMSIZE ?=
CPUCOUNT ?=


pi1b: platforms/pi1b.sh
	PLATFORM=pi1b NODENAME=pi MEMSIZE=512 CPUCOUNT=1 KERNEL=$(shell ls resources/firmwares/pi.kernel.1.*.tar.gz | head -1) $(MAKE) pi

pi1b-repair:
	MODE=repair $(MAKE) pi1b

pi: gentoo.sh
ifdef DEBUG
	bash gentoo.sh --dev=$(DEV) --kernel=$(KERNEL) --public-key=$(PUBKEY) --mode=$(MODE) --platform=$(PLATFORM) --mirrors=$(MIRRORS) --hostname=$(NODENAME) --mem=$(MEMSIZE) --cpu=$(CPUCOUNT) --debug=true
else
	bash gentoo.sh --dev=$(DEV) --kernel=$(KERNEL) --public-key=$(PUBKEY) --mode=$(MODE) --platform=$(PLATFORM) --mirrors=$(MIRRORS) --hostname=$(NODENAME) --mem=$(MEMSIZE) --cpu=$(CPUCOUNT)
endif

generic: platforms/generic.sh
	PLATFORM=generic $(MAKE) atom

generic-repair:
	MODE=repair $(MAKE) generic

atom: gentoo.sh
	echo -n $(DMCRYPTPASSWD) > $(CURDIR)/dmcrypt.key
ifdef DEBUG
	bash gentoo.sh --dev=$(DEV) --config=$(KCONFIG) --public-key=$(PUBKEY) --mode=$(MODE) --platform=$(PLATFORM) --dmcrypt-key=$(CURDIR)/dmcrypt.key --mirrors=$(MIRRORS) --debug=true
else
	bash gentoo.sh --dev=$(DEV) --config=$(KCONFIG) --public-key=$(PUBKEY) --mode=$(MODE) --platform=$(PLATFORM) --dmcrypt-key=$(CURDIR)/dmcrypt.key --mirrors=$(MIRRORS)
endif
	rm $(CURDIR)/dmcrypt.key
