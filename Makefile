obj-m := src/linuwu_sense.o

KVER  ?= $(shell uname -r)
KDIR  := /lib/modules/$(KVER)/build
PWD   := $(shell pwd)

MODNAME := linuwu_sense

.PHONY: all modules dkms-build sign clean install uninstall

all: modules sign

modules:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

dkms-build: modules

sign:
	# --- auto sign block ---
	
	#finding sign-file tool
	if [ -x "/lib/modules/$(KVER)/build/scripts/sign-file" ]; then \
		SIGN_TOOL="/lib/modules/$(KVER)/build/scripts/sign-file"; \
	elif [ -x "/usr/src/linux-headers-$(KVER)/scripts/sign-file" ]; then \
		SIGN_TOOL="/usr/src/linux-headers-$(KVER)/scripts/sign-file"; \
	else \
		echo "ERROR: sign-file tool not found"; \
		exit 1; \
	fi; \

	# assuming keys are located in a ~/module-signing folder named MOK....
	echo "Signing module linuwu_sense.ko using $$SIGN_TOOL"; \
	sudo $$SIGN_TOOL sha256 \
		$(HOME)/module-signing/MOK.priv \  
		$(HOME)/module-signing/MOK.der \
		$(PWD)/src/linuwu_sense.ko
	# --- end auto sign block ---

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

uninstall:
	@echo "Use the split uninstall flow instead:"
	@echo "  sudo ./scripts/system-setup.sh uninstall"
	@echo "  sudo ./scripts/dkms-remove.sh [version]"

install:
	@echo "Use the split install flow instead:"
	@echo "  sudo ./scripts/dkms-install.sh [version]"
	@echo "  sudo ./scripts/system-setup.sh install"
