#!/bin/bash
# Assemble a flashable Raspberry Pi 5 SD card image from the built bootc container.
#
# Layout (plain MBR, which the VideoCore firmware reads natively):
#   p1  FAT32 "CIDATA"  firmware, config.txt, bootc/entries/ostree-N/, cloud-init seed
#   p2  xfs   "boot"    /boot (ostree BLS entries + kernels)
#   p3  xfs   "root"    / (ostree sysroot)
#
# Same procedure as oci-native/archlinux-rpi's CI (verified on a Pi 5): bootc install
# to-filesystem with --bootloader none, then the first rpi-bootc-bootloader sync run from
# inside the image so it uses the same tools the Pi will use at upgrade time.
#
# Usage: sudo scripts/build-sd-image.sh <local-image> <target-imgref> <output.raw> [size]
#   local-image    image in root's containers-storage, e.g. localhost/fedora-hummingbird-rpi5:latest
#   target-imgref  what `bootc upgrade` on the Pi pulls, e.g. ghcr.io/owner/name:latest
#   size           raw image size, default 8G (cloud-init grows root on first boot)
set -euo pipefail

IMAGE="${1:?local image}"
TARGET_IMGREF="${2:?target imgref}"
OUT="${3:?output path}"
SIZE="${4:-8G}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[ "$(id -u)" = 0 ] || { echo "must run as root" >&2; exit 1; }

WORK="$(mktemp -d)"
LOOP=""
cleanup() {
    set +e
    for m in "$WORK/fat" "$WORK/target/boot" "$WORK/target"; do
        mountpoint -q "$m" && umount "$m"
    done
    [ -n "$LOOP" ] && losetup -d "$LOOP"
    rm -rf "$WORK"
}
trap cleanup EXIT

rm -f "$OUT"
truncate -s "$SIZE" "$OUT"
parted -s "$OUT" \
    mklabel msdos \
    mkpart primary fat32 4MiB 1028MiB \
    mkpart primary xfs 1028MiB 2052MiB \
    mkpart primary xfs 2052MiB 100%
parted -s "$OUT" set 1 lba on

LOOP="$(losetup -f --show -P "$OUT")"
udevadm settle || true
# CIDATA doubles as cloud-init's NoCloud seed label.
mkfs.vfat -F 32 -n CIDATA "${LOOP}p1"
mkfs.xfs -f -L boot "${LOOP}p2"
mkfs.xfs -f -L root "${LOOP}p3"

mkdir -p "$WORK/target" "$WORK/fat"
mount "${LOOP}p3" "$WORK/target"
mkdir -p "$WORK/target/boot"
mount "${LOOP}p2" "$WORK/target/boot"

# --bootloader none: the Pi has no bootloader to install. The firmware boots the
# os_prefix directories that rpi-bootc-bootloader maintains on p1.
podman run --rm --privileged --pid=host \
    --security-opt label=type:unconfined_t \
    -v /var/lib/containers:/var/lib/containers \
    -v /dev:/dev \
    -v "$WORK/target:/target" \
    "$IMAGE" \
    bootc install to-filesystem \
        --bootloader none \
        --generic-image \
        --skip-fetch-check \
        --target-imgref "$TARGET_IMGREF" \
        /target

# VideoCore firmware and the boot-partition seed files onto the FAT root.
mount "${LOOP}p1" "$WORK/fat"
DEPLOY="$(echo "$WORK"/target/ostree/deploy/default/deploy/*.0)"
test -d "$DEPLOY/usr/lib/ostree-boot"
cp -a --no-preserve=links,ownership "$DEPLOY/usr/lib/ostree-boot/." "$WORK/fat/"
cp "$REPO_ROOT"/boot-partition/{config-bootc-common.txt,meta-data,user-data,README.txt} "$WORK/fat/"
umount "$WORK/fat"
umount "$WORK/target/boot" "$WORK/target"

# First sync: writes config.txt, tryboot.txt and bootc/entries/ostree-1/ onto p1.
# The hook finds p1 by taking the /sysroot device and replacing its partition number with 1.
podman run --rm --privileged \
    -v /dev:/dev \
    --entrypoint /bin/bash \
    "$IMAGE" \
    -c "set -euxo pipefail
        mount ${LOOP}p3 /sysroot
        mount ${LOOP}p2 /boot
        grep '^options ' /boot/loader/entries/ostree-1.conf
        rpi-bootc-bootloader version
        rpi-bootc-bootloader sync
        umount /boot /sysroot"

# Sanity checks on what the firmware will read.
mount "${LOOP}p1" "$WORK/fat"
E="$WORK/fat/bootc/entries/ostree-1"
for f in config.txt config-bootc-default.txt "$E/vmlinuz" "$E/initrd" "$E/cmdline.txt" \
         "$E/bcm2712-rpi-5-b.dtb" "$E/bcm2712d0-rpi-5-b.dtb"; do
    case "$f" in /*) p="$f" ;; *) p="$WORK/fat/$f" ;; esac
    test -s "$p" || { echo "missing on boot partition: $f" >&2; exit 1; }
done
echo "--- config.txt"; cat "$WORK/fat/config.txt"
echo "--- cmdline.txt"; cat "$E/cmdline.txt"
umount "$WORK/fat"

echo "SD image ready: $OUT"
