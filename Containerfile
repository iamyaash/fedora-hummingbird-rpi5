# Pinned base: bump the date tag and digest together.
ARG BASE_IMAGE=quay.io/hummingbird-community/os-minimal:20261028@sha256:712da83e76023496164d92c70d91658feb8703fbb1a5e4fc012cb0cf4a78056f

FROM ${BASE_IMAGE}

# GRUB and shim are protected by dnf in /etc/dnf/protected.d, so drop the protection so dnf can remove it
RUN rm -f /etc/dnf/protected.d/grub2-efi-aa64.conf \
          /etc/dnf/protected.d/grub2-tools-minimal.conf \
          /etc/dnf/protected.d/shim.conf

# Raspberry Pi kernel and firmware from AlmaLinux el10 repo
COPY files/etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux-10 /etc/pki/rpm-gpg/
COPY files/etc/yum.repos.d/almalinux-rpi.repo /etc/yum.repos.d/

#  Fedora 44 repo and key:
# Hummingbird has no linux-firmware or brcmfmac-firmware, which the Pi 5 WiFi blobs need
COPY files/etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-44-primary /etc/pki/rpm-gpg/
COPY files/etc/yum.repos.d/fedora-44-firmware.repo /etc/yum.repos.d/

# Remove UEFI boot chain & bootupd from dnf directly during build time
# Remove bootupd and kernel leftover files
# Install Raspberry Pi kernel after removing /usr/lib/modules/*
# Move vmlinuz, initramfs, config to /usr/lib/modules/*
# Remove boot/* and clean /var/cache/ldconfig
RUN systemctl disable bootloader-update.service \
    && dnf -y remove grub2-efi-aa64 grub2-tools grub2-tools-minimal grub2-common \
       shim-aa64 efibootmgr bootupd \
       kernel kernel-core kernel-modules kernel-modules-core \
    && rm -rf /usr/lib/bootupd /usr/lib/modules/* /usr/lib/efi \
    && dnf -y install --setopt=install_weak_deps=False raspberrypi2-kernel4 raspberrypi2-firmware \
    linux-firmware-raspberrypi brcmfmac-firmware wireless-regdb \
    wpa_supplicant bluez NetworkManager-wifi \
    && systemctl enable bluetooth.service \
    && KVER=$(ls /usr/lib/modules) \
    && mv /boot/kernel-$KVER.img /usr/lib/modules/$KVER/vmlinuz \
    && mv /boot/initramfs-$KVER.img /usr/lib/modules/$KVER/initramfs.img \
    && mv /boot/config-$KVER /usr/lib/modules/$KVER/config \
    && mkdir -p /usr/share/raspberrypi2-firmware \
    && mv /boot/bootcode.bin /boot/LICENCE.broadcom /boot/start*.elf /boot/fixup*.dat /usr/share/raspberrypi2-firmware/ \
    && rm -rf /boot/* \
    && dnf clean all \
    && rm -rf /run/dnf /var/log/dnf5.log /var/cache/libdnf5 /var/cache/ldconfig

# Declare /var folders from NetworkManager and bluez, since bootc doesn't update /var
COPY files/usr/lib/tmpfiles.d/fedora-hummingbird-rpi5.conf /usr/lib/tmpfiles.d/

# brcmfmac drops off WiFi with power save on, so disable it
COPY files/usr/lib/NetworkManager/conf.d/50-rpi-wifi-powersave.conf /usr/lib/NetworkManager/conf.d/

# Override Hummingbird's kargs: the Pi 5 debug UART is ttyAMA10, not ttyS0
COPY files/usr/lib/bootc/kargs.d/00-base.toml /usr/lib/bootc/kargs.d/

# Let the video group use vcgencmd without sudo
COPY files/usr/lib/udev/rules.d/60-rpi-vcio.rules /usr/lib/udev/rules.d/

# Rebuild the initramfs: no-hostonly since the build host is not a Pi,
# with the xfs/erofs/overlay modules from 30-rpi.conf for root and composefs
COPY files/usr/lib/dracut/dracut.conf.d/30-rpi.conf /usr/lib/dracut/dracut.conf.d/
RUN KVER=$(ls /usr/lib/modules) \
    && dracut --force --no-hostonly --kver "$KVER" "/usr/lib/modules/$KVER/initramfs.img" \
    && lsinitrd "/usr/lib/modules/$KVER/initramfs.img" | grep -E '/(xfs|erofs|overlay)\.ko' \
    && rm -rf /var/cache/ldconfig

RUN bootc container lint --fatal-warnings
