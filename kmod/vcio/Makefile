# Out-of-tree build of vcio.ko.
#   make KDIR=/usr/src/kernels/<kver>
KDIR ?= /lib/modules/$(shell uname -r)/build

obj-m := vcio.o

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
