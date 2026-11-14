// SPDX-License-Identifier: GPL-2.0-only
/*
 * /dev/vcio: userspace access to the Raspberry Pi firmware mailbox property
 * interface. vcgencmd and vcmailbox use it, and rpi-bootc-bootloader uses
 * vcmailbox to set the tryboot flag.
 *
 * Adapted from the Raspberry Pi downstream kernel, drivers/char/broadcom/vcio.c
 * (rpi-6.12.y):
 *   Copyright (C) 2010 Broadcom
 *   Copyright (C) 2015 Noralf Trønnes
 *   Copyright (C) 2021 Raspberry Pi (Trading) Ltd.
 *
 * Changes for the upstream (Fedora) kernel and DTBs:
 * - The downstream driver binds to a "raspberrypi,vcio" device tree node, which
 *   only downstream DTBs have. This module finds the firmware node itself and
 *   registers the misc device when it is loaded.
 * - The buffer size from userspace is checked before use.
 * The ioctl ABI is unchanged.
 */

#include <linux/compat.h>
#include <linux/miscdevice.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/sizes.h>
#include <linux/slab.h>
#include <linux/string.h>
#include <linux/uaccess.h>
#include <soc/bcm2835/raspberrypi-firmware.h>

#define VCIO_IOC_MAGIC 100
#define IOCTL_MBOX_PROPERTY _IOWR(VCIO_IOC_MAGIC, 0, char *)
#ifdef CONFIG_COMPAT
#define IOCTL_MBOX_PROPERTY32 _IOWR(VCIO_IOC_MAGIC, 0, compat_uptr_t)
#endif

/* Buffer: size word, request/response code word, tags, end tag. */
#define VCIO_MIN_SIZE 12
#define VCIO_MAX_SIZE SZ_1M

static struct rpi_firmware *vcio_fw;

static int vcio_user_property_list(void __user *user)
{
	u32 *buf, size;
	int ret;

	/* The first 32-bit word is the size of the whole buffer */
	if (copy_from_user(&size, user, sizeof(size)))
		return -EFAULT;
	if (size < VCIO_MIN_SIZE || size > VCIO_MAX_SIZE)
		return -EINVAL;

	buf = memdup_user(user, size);
	if (IS_ERR(buf))
		return PTR_ERR(buf);

	/* Strip off the protocol encapsulation: size, code and end tag */
	ret = rpi_firmware_property_list(vcio_fw, &buf[2], size - VCIO_MIN_SIZE);
	if (ret)
		goto out;

	buf[1] = RPI_FIRMWARE_STATUS_SUCCESS;
	if (copy_to_user(user, buf, size))
		ret = -EFAULT;
out:
	kfree(buf);
	return ret;
}

static long vcio_ioctl(struct file *file, unsigned int cmd, unsigned long arg)
{
	switch (cmd) {
	case IOCTL_MBOX_PROPERTY:
		return vcio_user_property_list((void __user *)arg);
	default:
		return -ENOTTY;
	}
}

#ifdef CONFIG_COMPAT
static long vcio_compat_ioctl(struct file *file, unsigned int cmd,
			      unsigned long arg)
{
	switch (cmd) {
	case IOCTL_MBOX_PROPERTY32:
		return vcio_user_property_list(compat_ptr(arg));
	default:
		return -ENOTTY;
	}
}
#endif

static const struct file_operations vcio_fops = {
	.owner = THIS_MODULE,
	.unlocked_ioctl = vcio_ioctl,
#ifdef CONFIG_COMPAT
	.compat_ioctl = vcio_compat_ioctl,
#endif
};

static struct miscdevice vcio_misc = {
	.minor = MISC_DYNAMIC_MINOR,
	.name = "vcio",
	.fops = &vcio_fops,
};

static int __init vcio_init(void)
{
	struct device_node *np;
	int ret;

	np = of_find_compatible_node(NULL, NULL, "raspberrypi,bcm2835-firmware");
	if (!np) {
		pr_err("vcio: no raspberrypi,bcm2835-firmware node in the device tree\n");
		return -ENODEV;
	}

	/* Takes a reference; NULL if the firmware driver hasn't probed yet */
	vcio_fw = rpi_firmware_get(np);
	of_node_put(np);
	if (!vcio_fw) {
		pr_err("vcio: Raspberry Pi firmware driver not ready\n");
		return -ENODEV;
	}

	ret = misc_register(&vcio_misc);
	if (ret) {
		rpi_firmware_put(vcio_fw);
		return ret;
	}

	return 0;
}

static void __exit vcio_exit(void)
{
	misc_deregister(&vcio_misc);
	rpi_firmware_put(vcio_fw);
}

module_init(vcio_init);
module_exit(vcio_exit);

MODULE_AUTHOR("Gray Girling");
MODULE_AUTHOR("Noralf Trønnes");
MODULE_DESCRIPTION("Mailbox userspace access (/dev/vcio) for upstream DTBs");
MODULE_LICENSE("GPL");
