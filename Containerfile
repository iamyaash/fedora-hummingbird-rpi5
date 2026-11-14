# Pinned base: bump the date tag and digest together. Its Fedora kernel is the one
# that boots, so a bump also moves the kernel (and rebuilds vcio.ko against it).
ARG BASE_IMAGE=quay.io/hummingbird-community/os-minimal:20261028@sha256:712da83e76023496164d92c70d91658feb8703fbb1a5e4fc012cb0cf4a78056f

# Only used to compile vcio.ko and unpack the kernel; nothing from it ships.
ARG BUILDER_IMAGE=registry.fedoraproject.org/fedora:44

ARG RPI_BOOTC_BOOTLOADER_VERSION=v0.0.8

FROM ${BASE_IMAGE} AS base

# Build against the base image's Fedora kernel:
# - vcio.ko: /dev/vcio for vcgencmd, vcmailbox and tryboot. The Fedora kernel has no
#   CONFIG_BCM_VCIO. kernel-devel comes from Koji by exact NVR, because the Fedora
#   updates repo only carries the newest kernel.
# - 8250_bcm7271.ko: the Pi 5 Bluetooth UART driver. The Fedora kernel has no
#   CONFIG_SERIAL_8250_BCM7271. Unmodified upstream source, vendored at the kernel's version.
# - Image: the raw arm64 kernel. Fedora's vmlinuz is an EFI zboot wrapper around a
#   zstd payload, which the Pi firmware can't boot.
FROM ${BUILDER_IMAGE} AS kernel-build
COPY kmod/vcio/ /src/vcio/
COPY kmod/bcm7271-uart/ /src/bcm7271-uart/
RUN --mount=type=bind,from=base,source=/usr/lib/modules,target=/base-modules \
    set -eux; \
    KVER="$(ls /base-modules)"; \
    test "$(echo "$KVER" | wc -w)" = 1; \
    ARCH="${KVER##*.}"; test "$ARCH" = "$(uname -m)"; \
    VER="${KVER%%-*}"; REL="${KVER#*-}"; REL="${REL%.*}"; \
    dnf -y install --setopt=install_weak_deps=False gcc make kmod zstd \
        "https://kojipkgs.fedoraproject.org/packages/kernel/$VER/$REL/$ARCH/kernel-devel-$KVER.rpm"; \
    make -C /src/vcio KDIR="/usr/src/kernels/$KVER"; \
    modinfo -F vermagic /src/vcio/vcio.ko | grep -q "^$KVER "; \
    test "$(cat /src/bcm7271-uart/VERSION)" = "$VER" \
        || { echo "kmod/bcm7271-uart is for $(cat /src/bcm7271-uart/VERSION), kernel is $VER: run make -C kmod/bcm7271-uart update KVERSION=$VER" >&2; exit 1; }; \
    make -C /src/bcm7271-uart KDIR="/usr/src/kernels/$KVER"; \
    BT=/src/bcm7271-uart/8250/8250_bcm7271.ko; \
    modinfo -F vermagic "$BT" | grep -q "^$KVER "; \
    modinfo -F alias "$BT" | grep -qx 'of:N\*T\*Cbrcm,bcm7271-uart'; \
    mkdir -p /out; cp /src/vcio/vcio.ko "$BT" /out/; echo "$KVER" > /out/kver; \
    Z="/base-modules/$KVER/vmlinuz"; \
    test "$(dd if="$Z" bs=1 skip=4 count=4 status=none)" = zimg; \
    test "$(dd if="$Z" bs=1 skip=24 count=4 status=none)" = zstd; \
    OFF="$(od -An -tu4 -j8 -N4 "$Z" | tr -d ' ')"; \
    SIZE="$(od -An -tu4 -j12 -N4 "$Z" | tr -d ' ')"; \
    dd if="$Z" bs=4M iflag=skip_bytes,count_bytes skip="$OFF" count="$SIZE" status=none \
        | zstd -dc > /out/Image; \
    test "$(dd if=/out/Image bs=1 skip=56 count=4 status=none)" = ARMd

FROM ${BASE_IMAGE}
ARG RPI_BOOTC_BOOTLOADER_VERSION

# GRUB and shim are protected by dnf in /etc/dnf/protected.d, so drop the protection so dnf can remove it
RUN rm -f /etc/dnf/protected.d/grub2-efi-aa64.conf \
          /etc/dnf/protected.d/grub2-tools-minimal.conf \
          /etc/dnf/protected.d/shim.conf

# Raspberry Pi VideoCore firmware, Pi WiFi/BT blobs and vcgencmd/vcmailbox from the
# AlmaLinux el10 repo. Not the kernel: the base image's Fedora kernel is kept.
COPY files/etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux-10 /etc/pki/rpm-gpg/
COPY files/etc/yum.repos.d/almalinux-rpi.repo /etc/yum.repos.d/

#  Fedora 44 repo and key:
# Hummingbird has no linux-firmware or brcmfmac-firmware, which the Pi 5 WiFi blobs need
COPY files/etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-44-primary /etc/pki/rpm-gpg/
COPY files/etc/yum.repos.d/fedora-44-firmware.repo /etc/yum.repos.d/

# Remove the UEFI boot chain and bootupd; keep the base's Fedora kernel
# Install the VideoCore firmware, WiFi/BT firmware and tools
# Stage VideoCore firmware in /usr/lib/ostree-boot for the FAT partition
# Remove boot/* and clean /var/cache/ldconfig
RUN systemctl disable bootloader-update.service \
    && dnf -y remove grub2-efi-aa64 grub2-tools grub2-tools-minimal grub2-common \
       shim-aa64 efibootmgr bootupd \
    && rm -rf /usr/lib/bootupd /usr/lib/efi \
    && dnf -y install --setopt=install_weak_deps=False raspberrypi2-firmware \
    linux-firmware-raspberrypi raspberrypi-userland brcmfmac-firmware wireless-regdb \
    wpa_supplicant bluez NetworkManager-wifi \
    cloud-init cloud-utils-growpart xfsprogs jq \
    && rpm -q kernel-core \
    && ! rpm -q raspberrypi2-kernel4 \
    && mkdir -p /usr/lib/ostree-boot \
    && mv /boot/bootcode.bin /boot/LICENCE.broadcom /boot/start*.elf /boot/fixup*.dat /usr/lib/ostree-boot/ \
    && rm -rf /boot/* \
    && dnf clean all \
    && rm -rf /run/dnf /var/log/dnf5.log /var/cache/libdnf5 /var/cache/ldconfig

# Make the Fedora kernel bootable by the Pi firmware:
# - vmlinuz becomes the raw Image. .vmlinuz.hmac (FIPS) hashed the zboot file, so it goes.
# - vcio.ko goes in extra/ and loads at boot via modules-load.d (no DT node to match).
# - 8250_bcm7271.ko goes in extra/ too. It loads by DT alias when the Bluetooth UART node
#   probes, then hci_uart and btbcm bring up hci0.
# - The Pi 5 DTBs are staged under /usr/share/raspberrypi2-kernel*/<kver>/boot/, the
#   path rpi-bootc-bootloader copies from. The firmware loads the downstream file names,
#   so upstream bcm2712-d-rpi-5-b.dtb is installed as bcm2712d0-rpi-5-b.dtb.
COPY --from=kernel-build /out/ /tmp/kernel-build/
COPY files/usr/lib/modules-load.d/vcio.conf /usr/lib/modules-load.d/
RUN KVER=$(ls /usr/lib/modules) \
    && test "$KVER" = "$(cat /tmp/kernel-build/kver)" \
    && install -m 0755 /tmp/kernel-build/Image /usr/lib/modules/$KVER/vmlinuz \
    && rm -f /usr/lib/modules/$KVER/.vmlinuz.hmac \
    && install -D -m 0644 /tmp/kernel-build/vcio.ko /usr/lib/modules/$KVER/extra/vcio.ko \
    && install -m 0644 /tmp/kernel-build/8250_bcm7271.ko /usr/lib/modules/$KVER/extra/ \
    && depmod -a $KVER \
    && modinfo -k $KVER vcio > /dev/null \
    && grep -q 'brcm,bcm7271-uart.* 8250_bcm7271$' /usr/lib/modules/$KVER/modules.alias \
    && D=/usr/share/raspberrypi2-kernel-fedora/$KVER/boot \
    && install -D -m 0644 /usr/lib/modules/$KVER/dtb/broadcom/bcm2712-rpi-5-b.dtb $D/bcm2712-rpi-5-b.dtb \
    && install -m 0644 /usr/lib/modules/$KVER/dtb/broadcom/bcm2712-d-rpi-5-b.dtb $D/bcm2712d0-rpi-5-b.dtb \
    && test "$(ls -d /usr/share/raspberrypi2-kernel*/*/boot | wc -l)" = 1 \
    && echo '# Per-deployment firmware settings (board-wide ones go in config-bootc-common.txt).' \
       > /usr/lib/modules/$KVER/rpi-config.txt \
    && rm -rf /tmp/kernel-build /var/cache/ldconfig

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
COPY files/usr/lib/tmpfiles.d/hummingbird-rpi5.conf /usr/lib/tmpfiles.d/

# brcmfmac drops off WiFi with power save on, so disable it
COPY files/usr/lib/NetworkManager/conf.d/50-rpi-wifi-powersave.conf /usr/lib/NetworkManager/conf.d/

# Override Hummingbird's kargs: the Pi 5 debug UART is ttyAMA10, not ttyS0
COPY files/usr/lib/bootc/kargs.d/00-base.toml /usr/lib/bootc/kargs.d/

# vcgencmd and vcmailbox come from raspberrypi-userland: vcgencmd for firmware queries
# (temperature, throttling), vcmailbox for `rpi-bootc-bootloader tryboot`.
# The udev rule lets the video group use them without sudo.
COPY files/usr/lib/udev/rules.d/60-rpi-vcio.rules /usr/lib/udev/rules.d/
RUN test -x /usr/bin/vcgencmd && test -x /usr/bin/vcmailbox

# Rebuild the initramfs: no-hostonly since the build host is not a Pi, with the
# filesystem and SD card modules from 30-rpi.conf. Fail if any of them is missing.
COPY files/usr/lib/dracut/dracut.conf.d/30-rpi.conf /usr/lib/dracut/dracut.conf.d/
RUN KVER=$(ls /usr/lib/modules) \
    && dracut --force --no-hostonly --kver "$KVER" "/usr/lib/modules/$KVER/initramfs.img" \
    && lsinitrd "/usr/lib/modules/$KVER/initramfs.img" > /tmp/initrd.lst \
    && for m in xfs erofs overlay mmc_block sdhci sdhci-pltfm sdhci-brcmstb; do \
         grep -qE "/$m\.ko" /tmp/initrd.lst || { echo "initramfs is missing $m" >&2; exit 1; }; \
       done \
    && rm -rf /tmp/initrd.lst /var/cache/ldconfig

RUN rm -rf /run/cloud-init

RUN bootc container lint --fatal-warnings
