# Out-of-tree build of 8250_bcm7271.ko, the driver for the Pi 5 Bluetooth UART
# (serial@7d50c000, brcm,bcm7271-uart). Fedora's kernel doesn't set
# CONFIG_SERIAL_8250_BCM7271, so no Bluetooth controller appears without it.
#
# The driver is upstream and unmodified. Its sources, including the internal 8250.h,
# are fetched from the stable tree at the kernel's exact version, so the private
# header always matches the kernel the module loads into.
#   make KDIR=/usr/src/kernels/<kver> KVERSION=<x.y.z>
KDIR ?= /lib/modules/$(shell uname -r)/build
KVERSION ?= $(firstword $(subst -, ,$(shell uname -r)))
STABLE := https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/drivers/tty/serial
SOURCES := 8250/8250_bcm7271.c 8250/8250.h serial_mctrl_gpio.h

all: $(SOURCES)
	$(MAKE) -C $(KDIR) M=$(CURDIR)/8250 modules

$(SOURCES):
	mkdir -p $(dir $@)
	curl -fsSL -o $@ "$(STABLE)/$@?h=v$(KVERSION)"

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/8250 clean
	rm -f $(SOURCES)

.PHONY: all clean
