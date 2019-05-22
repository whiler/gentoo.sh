DEV ?= /dev/sdb
KCONFIG ?= $(CURDIR)/kernel.config
PUBKEY ?= $(HOME)/.ssh/id_rsa.pub
MODE ?= install
PLATFORM ?= base
DEBUG ?= true
DMCRYPTPASSWD ?= dMcr794
KERNEL ?=
MIRRORS ?= https://mirrors.tuna.tsinghua.edu.cn/gentoo

pi1b:
	PLATFORM=pi1b $(MAKE) pi

pi1b-repair:
	MODE=repair $(MAKE) pi1b

pi: gentoo.sh
ifdef DEBUG
	bash gentoo.sh --dev=$(DEV) --kernel=$(shell ls resources/firmwares/pi.kernel.1.*.tar.gz | head -1) --public-key=$(PUBKEY) --mode=$(MODE) --platform=$(PLATFORM) --mirrors=$(MIRRORS) --debug=true
else
	bash gentoo.sh --dev=$(DEV) --kernel=$(shell ls resources/firmwares/pi.kernel.1.*.tar.gz | head -1) --public-key=$(PUBKEY) --mode=$(MODE) --platform=$(PLATFORM) --mirrors=$(MIRRORS)
endif

generic:
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
