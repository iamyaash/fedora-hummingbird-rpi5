# fedora-hummingbird-rpi5

Fedora Hummingbird (a bootc, image-based OS) on the Raspberry Pi 5, booted directly by the Pi's own firmware, without UEFI, U-Boot or GRUB.

**Status:** work in progress, not yet tested on hardware.

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
runner and uploads a flashable SD image as a workflow artifact.

Locally, on an arm64 host:

```sh
sudo podman build -t localhost/flhb-rpi:latest -f Containerfile .
sudo scripts/build-sd-image.sh localhost/flhb-rpi:latest ghcr.io/<owner>/fedora-hummingbird-rpi5:latest fedora-hummingbird-rpi5.raw
```

## Flash and first boot

```sh
xzcat fedora-hummingbird-rpi5-*.raw.xz | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress
```

Before booting, mount the card's first partition (`CIDATA`) and put your SSH public key
into `user-data`. Boot with ethernet connected, find `hummingbird-rpi` in your router's
client list, then run `ssh hummingbird@<ip>`.
