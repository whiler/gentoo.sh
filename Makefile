DEV ?= /dev/sdb
KCONFIG ?= $(CURDIR)/kernel.config
PUBKEY ?= $(HOME)/.ssh/id_rsa.pub
MODE ?= install
PLATFORM ?= base
DEBUG ?= true

base:
	PLATFORM=base $(MAKE) atom

base-repair:
	MODE=repair $(MAKE) base

atom: gentoo.sh
ifdef DEBUG
	bash gentoo.sh --dev=$(DEV) --config=$(KCONFIG) --public-key=$(PUBKEY) --mode=$(MODE) --platform=$(PLATFORM) --debug=true
else
	bash gentoo.sh --dev=$(DEV) --config=$(KCONFIG) --public-key=$(PUBKEY) --mode=$(MODE) --platform=$(PLATFORM)
endif
