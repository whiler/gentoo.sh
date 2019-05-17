DEV ?= /dev/sdb
KCONFIG ?= $(CURDIR)/kernel.config
PUBKEY ?= $(HOME)/.ssh/id_rsa.pub
MODE ?= install
PLATFORM ?= base
DEBUG ?= true
DMCRYPTPASSWD ?= dMcr794
KERNEL ?=

Pi1B:
	PLATFORM=Pi1B $(MAKE) pi

# can not chroot
pi:
	bash gentoo.sh --dev=$(DEV) --public-key=$(PUBKEY) --mode=$(MODE) --platform=$(PLATFORM) --kernel=$(KERNEL)

public:
	PLATFORM=public $(MAKE) atom

public-repair:
	MODE=repair $(MAKE) public

generic:
	PLATFORM=generic $(MAKE) atom

generic-repair:
	MODE=repair $(MAKE) generic

base:
	PLATFORM=base $(MAKE) atom

base-repair:
	MODE=repair $(MAKE) base

atom: gentoo.sh
	echo -n $(DMCRYPTPASSWD) > $(CURDIR)/dmcrypt.key
ifdef DEBUG
	bash gentoo.sh --dev=$(DEV) --config=$(KCONFIG) --public-key=$(PUBKEY) --mode=$(MODE) --platform=$(PLATFORM) --dmcrypt-key=$(CURDIR)/dmcrypt.key --debug=true
else
	bash gentoo.sh --dev=$(DEV) --config=$(KCONFIG) --public-key=$(PUBKEY) --mode=$(MODE) --platform=$(PLATFORM) --dmcrypt-key=$(CURDIR)/dmcrypt.key
endif
