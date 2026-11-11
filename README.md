# fedora-hummingbird-rpi5

Fedora Hummingbird (a bootc, image-based OS) on the Raspberry Pi 5, booted directly by the Pi's own firmware, without UEFI, U-Boot or GRUB.

**Status:** Work in progress. Tested on a Raspberry Pi 5 (8 GB) with no known issues so far; further testing is ongoing.

## How

Based on [AlmaLinux/bootc-images-rpi](https://github.com/AlmaLinux/bootc-images-rpi) and
[oci-native/archlinux-rpi](https://github.com/oci-native/archlinux-rpi):

- **Base:** `quay.io/hummingbird-community/os-minimal`, pinned by date and digest.
- **Removed:** GRUB, shim, bootupd and the Fedora mainline kernel.
- **Added:**
  - AlmaLinux's Raspberry Pi kernel (`raspberrypi2-kernel4`) and VideoCore firmware
  - Pi WiFi/BT firmware, `wpa_supplicant`, `bluez` and cloud-init from Fedora 44
- **Updates:** [rpi-bootc-bootloader](https://github.com/kfox1111/rpi-bootc-bootloader) copies each
  bootc deployment onto the FAT partition and points the firmware's `os_prefix` at it,
  so `bootc upgrade` and rollback work with no bootloader.

## Build

CI ([`.github/workflows/build.yml`](.github/workflows/build.yml)) builds on a native arm64
runner and uploads a compressed, flashable SD image as a workflow artifact.

To build locally, on an arm64 host with podman (as root):

```sh
# 1. Build the bootc container image
sudo podman build -t localhost/fedora-hummingbird-rpi5:latest -f Containerfile .

# 2. Assemble the SD card image
#    args: <local-image> <target-imgref for bootc upgrade> <output.raw> [size, default 8G]
sudo scripts/build-sd-image.sh \
  localhost/fedora-hummingbird-rpi5:latest \
  ghcr.io/<owner>/fedora-hummingbird-rpi5:latest \
  fedora-hummingbird-rpi5.raw

# 3. Optional: compress
xz -T0 fedora-hummingbird-rpi5.raw
```

## Flash and first boot

```sh
xzcat fedora-hummingbird-rpi5-*.raw.xz | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress
```

Before first boot, mount the card's first partition (`CIDATA`) and add your SSH public key
to `user-data`. Boot with ethernet connected, find `hummingbird-rpi` in your router's
client list, then run `ssh hummingbird@<ip>`.

> Thanks to [Claude](https://claude.ai) (Anthropic), which helped with guidance, reviews, script building and documentation edits.