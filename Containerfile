# Pinned base: bump the date tag and digest together.
ARG BASE_IMAGE=quay.io/hummingbird-community/os-minimal:20261028@sha256:712da83e76023496164d92c70d91658feb8703fbb1a5e4fc012cb0cf4a78056f

ARG RPI_BOOTC_BOOTLOADER_VERSION=v0.0.8

FROM ${BASE_IMAGE}
ARG RPI_BOOTC_BOOTLOADER_VERSION

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
# Stage VideoCore firmware in /usr/lib/ostree-boot for the FAT partition
# Remove boot/* and clean /var/cache/ldconfig
RUN systemctl disable bootloader-update.service \
    && dnf -y remove grub2-efi-aa64 grub2-tools grub2-tools-minimal grub2-common \
       shim-aa64 efibootmgr bootupd \
       kernel kernel-core kernel-modules kernel-modules-core \
    && rm -rf /usr/lib/bootupd /usr/lib/modules/* /usr/lib/efi \
    && dnf -y install --setopt=install_weak_deps=False raspberrypi2-kernel4 raspberrypi2-firmware \
    linux-firmware-raspberrypi raspberrypi-userland brcmfmac-firmware wireless-regdb \
    wpa_supplicant bluez NetworkManager-wifi \
    cloud-init cloud-utils-growpart xfsprogs jq \
    && KVER=$(ls /usr/lib/modules) \
    && mv /boot/kernel-$KVER.img /usr/lib/modules/$KVER/vmlinuz \
    && mv /boot/initramfs-$KVER.img /usr/lib/modules/$KVER/initramfs.img \
    && mv /boot/config-$KVER /usr/lib/modules/$KVER/config \
    && test -f /usr/share/raspberrypi2-kernel4/$KVER/boot/bcm2712-rpi-5-b.dtb \
    && test -f /usr/share/raspberrypi2-kernel4/$KVER/boot/bcm2712d0-rpi-5-b.dtb \
    && mkdir -p /usr/lib/ostree-boot \
    && mv /boot/bootcode.bin /boot/LICENCE.broadcom /boot/start*.elf /boot/fixup*.dat /usr/lib/ostree-boot/ \
    && echo '# Per-deployment firmware settings (board-wide ones go in config-bootc-common.txt).' \
       > /usr/lib/modules/$KVER/rpi-config.txt \
    && rm -rf /boot/* \
    && dnf clean all \
    && rm -rf /run/dnf /var/log/dnf5.log /var/cache/libdnf5 /var/cache/ldconfig

# rpi-bootc-bootloader: mirrors each bootc deployment onto the FAT partition
# (bootc/entries/ostree-N/) and flips os_prefix in config.txt
RUN base="https://raw.githubusercontent.com/kfox1111/rpi-bootc-bootloader/refs/tags/${RPI_BOOTC_BOOTLOADER_VERSION}" \
    && mkdir -p /usr/lib/systemd/system/ostree-finalize-staged.service.d \
    && curl -fsSL -o /usr/bin/rpi-bootc-bootloader "$base/rpi-bootc-bootloader" \
    && curl -fsSL -o /usr/lib/systemd/system/ostree-finalize-staged.service.d/rpi-bootc-bootloader.conf \
       "$base/system/ostree-finalize-staged.service.d/rpi-bootc-bootloader.conf" \
    && chmod 0755 /usr/bin/rpi-bootc-bootloader \
    && grep -q "VERSION=\"${RPI_BOOTC_BOOTLOADER_VERSION}\"" /usr/bin/rpi-bootc-bootloader

# cloud-init: grow the partition behind /sysroot and resize /var, since / is
# read-only composefs on ostree (same patch as AlmaLinux's bootstrap image)
COPY files/etc/cloud/ /etc/cloud/
RUN f="$(echo /usr/lib/python3*/site-packages/cloudinit/config/cc_resizefs.py)" \
    && grep -q 'resize_what = "/"' "$f" \
    && sed -i 's@resize_what = "/"@resize_what = "/var"@' "$f" \
    && rm -f "$(dirname "$f")"/__pycache__/cc_resizefs.*.pyc

# Enable network, SSH, bluetooth, clock and cloud-init services via preset
COPY files/usr/lib/systemd/system-preset/70-rpi.preset /usr/lib/systemd/system-preset/
RUN systemctl preset NetworkManager.service sshd.service bluetooth.service chronyd.service \
    cloud-init-main.service cloud-init-local.service cloud-init-network.service \
    cloud-config.service cloud-final.service

# The Pi has no battery clock and Hummingbird's chrony pool doesn't resolve,
# so HTTPS fails on cert dates. Use Fedora's pool; fail if the line moves
RUN grep -q '2\.hummingbird\.pool\.ntp\.org' /etc/chrony.conf \
    && sed -i 's/2\.hummingbird\.pool\.ntp\.org/2.fedora.pool.ntp.org/' /etc/chrony.conf \
    && grep -q '2\.fedora\.pool\.ntp\.org' /etc/chrony.conf

# Declare /var folders from NetworkManager, bluez and cloud-init, since bootc doesn't update /var
COPY files/usr/lib/tmpfiles.d/fedora-hummingbird-rpi5.conf /usr/lib/tmpfiles.d/

# brcmfmac drops off WiFi with power save on, so disable it
COPY files/usr/lib/NetworkManager/conf.d/50-rpi-wifi-powersave.conf /usr/lib/NetworkManager/conf.d/

# Override Hummingbird's kargs: the Pi 5 debug UART is ttyAMA10, not ttyS0
COPY files/usr/lib/bootc/kargs.d/00-base.toml /usr/lib/bootc/kargs.d/

# vcgencmd and vcmailbox come from raspberrypi-userland: vcgencmd for firmware queries
# (temperature, throttling), vcmailbox for `rpi-bootc-bootloader tryboot`.
# The udev rule lets the video group use them without sudo.
COPY files/usr/lib/udev/rules.d/60-rpi-vcio.rules /usr/lib/udev/rules.d/
RUN test -x /usr/bin/vcgencmd && test -x /usr/bin/vcmailbox

# Rebuild the initramfs: no-hostonly since the build host is not a Pi,
# with the xfs/erofs/overlay modules from 30-rpi.conf for root and composefs
COPY files/usr/lib/dracut/dracut.conf.d/30-rpi.conf /usr/lib/dracut/dracut.conf.d/
RUN KVER=$(ls /usr/lib/modules) \
    && dracut --force --no-hostonly --kver "$KVER" "/usr/lib/modules/$KVER/initramfs.img" \
    && lsinitrd "/usr/lib/modules/$KVER/initramfs.img" | grep -E '/(xfs|erofs|overlay)\.ko' \
    && rm -rf /var/cache/ldconfig

RUN rm -rf /run/cloud-init

RUN bootc container lint --fatal-warnings
