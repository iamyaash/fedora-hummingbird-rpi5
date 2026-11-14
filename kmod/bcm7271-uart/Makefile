# Out-of-tree build of 8250_bcm7271.ko, the driver for the Pi 5 Bluetooth UART
# (serial@7d50c000, brcm,bcm7271-uart). Fedora's kernel doesn't set
# CONFIG_SERIAL_8250_BCM7271, so no Bluetooth controller appears without it.
#
# The sources are the unmodified upstream driver, vendored from the kernel.org stable
# tree at the version in VERSION. 8250.h is a private kernel header, so it must match
# the kernel the module loads into: the image build fails if VERSION doesn't match the
# base kernel. After a base image bump, run `make update KVERSION=<x.y.z>` and commit.
#   make KDIR=/usr/src/kernels/<kver>
KDIR ?= /lib/modules/$(shell uname -r)/build
STABLE := https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/drivers/tty/serial
SOURCES := 8250/8250_bcm7271.c 8250/8250.h serial_mctrl_gpio.h

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/8250 modules

update:
	test -n "$(KVERSION)"
	for f in $(SOURCES); do curl -fsSL -o "$$f" "$(STABLE)/$$f?h=v$(KVERSION)" || exit 1; done
	echo "$(KVERSION)" > VERSION

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/8250 clean

.PHONY: all update clean
