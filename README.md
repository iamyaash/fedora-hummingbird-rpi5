# Hummingbird on Raspberry Pi 5 (unstable)

> **Experimental and unstable.** This project is in a testing phase. Every image, tag and SD
> card image it publishes is marked `unstable`. Expect breaking changes, and don't use it for
> anything you can't reflash. A stable channel will come later.

Hummingbird OS (a bootc, image-based OS) on the Raspberry Pi 5, booted directly by the Pi's
own firmware, without UEFI, U-Boot or GRUB. The image mixes three sources: Hummingbird
userspace, the Fedora 44 kernel that ships in the Hummingbird base image, and Raspberry Pi
firmware and tools from AlmaLinux. The image is named `hummingbird-rpi5`.

**Status:** Unstable, work in progress. Only the Raspberry Pi 5 is supported (`bcm2712` device trees
only). Tested on a Pi 5 (8 GB) on 2026-11-14, from a fresh flash of the CI image:

- **Works:** boot from the Pi firmware, SSH, Ethernet (`end0`), WiFi (`wlan0`), Bluetooth
  (`hci0`, scan tested), cloud-init
  first boot with root and `/var` growth, `/dev/vcio`, `vcgencmd`, `vcmailbox`, tryboot,
  watchdog (`bcm2835_wdt`), hwmon and thermal sysfs, no failed units. `bootc upgrade` and
  `bootc switch` work.
- **Untested:** HDMI with a monitor, the power button, a power cut during `bootc upgrade`.
- **Not supported:** `bootc rollback`. Roll back with tryboot instead
  (see [Upgrades and rollback](#upgrades-and-rollback)).

## How

Based on [AlmaLinux/bootc-images-rpi](https://github.com/AlmaLinux/bootc-images-rpi) and
[oci-native/archlinux-rpi](https://github.com/oci-native/archlinux-rpi).

| Part | Comes from |
|---|---|
| Base and userspace (systemd, bootc, ostree, dracut, NetworkManager, chrony) | `quay.io/hummingbird-community/os-minimal`, pinned by date and digest |
| Kernel | Fedora 44 kernel in the base image (`7.2.13-200.fc44` at the current pin) |
| Device trees | Upstream Fedora Pi 5 DTBs from the same kernel |
| `/dev/vcio` | `vcio.ko`, built from [`kmod/vcio/`](kmod/vcio/) at build time |
| VideoCore firmware | AlmaLinux `raspberrypi2-firmware` |
| Pi WiFi/BT firmware | AlmaLinux `linux-firmware-raspberrypi` |
| `vcgencmd`, `vcmailbox` | AlmaLinux `raspberrypi-userland` |
| `linux-firmware`, `brcmfmac-firmware`, `wireless-regdb`, `iw`, `wpa_supplicant`, `bluez`, `cloud-init`, `cloud-utils-growpart`, `xfsprogs`, `jq` | Fedora 44 |
| Boot entries on the FAT partition | [rpi-bootc-bootloader](https://github.com/kfox1111/rpi-bootc-bootloader) v0.0.8 |

GRUB, shim and bootupd are removed.

Details:

- **Kernel updates** come from bumping the pinned base image (date tag and digest together),
  not from a separate kernel repo.
- **Kernel format:** Fedora's `vmlinuz` is an EFI zboot (zstd) wrapper that the Pi firmware
  can't boot. The build extracts the raw arm64 Image (~79 MB) and installs it as `vmlinuz`.
- **`/dev/vcio`** is needed by `vcgencmd`, `vcmailbox` and rpi-bootc-bootloader's tryboot.
  Fedora's kernel has no `CONFIG_BCM_VCIO`, so `kmod/vcio/vcio.c` is the downstream Raspberry
  Pi driver, adapted to bind without a `raspberrypi,vcio` DT node. A Fedora 44 builder stage
  compiles it against `kernel-devel` for the exact base kernel, fetched from Koji by NVR
  (the Fedora updates repo only keeps the newest kernel). It loads at boot via
  `modules-load.d`. The module is unsigned, so the kernel is tainted (`O`/`E`); it loads
  because `MODULE_SIG_FORCE` is off. If a base image bump changes the kernel API, the vcio
  build fails. That's intended.
- **Bluetooth:** Fedora's kernel has no `CONFIG_SERIAL_8250_BCM7271`, the driver for the
  Pi 5 Bluetooth UART (`brcm,bcm7271-uart`). `kmod/bcm7271-uart` builds the unmodified
  upstream driver out of tree. Its sources, including the internal `8250.h`, are fetched from
  the kernel.org stable tree at the base kernel's exact version, so the private header matches
  the running kernel. It loads by DT alias; `hci_uart` and `btbcm` then bring up `hci0` with
  the Pi 5 firmware patch (`BCM4345C0.raspberrypi,5-model-b.hcd`). Unsigned, like `vcio.ko`.
- **Device trees:** `bcm2712-rpi-5-b.dtb`, and upstream `bcm2712-d-rpi-5-b.dtb` installed as
  `bcm2712d0-rpi-5-b.dtb` (the name the firmware loads). They're staged under
  `/usr/share/raspberrypi2-kernel-fedora/<kver>/boot/`, where rpi-bootc-bootloader copies
  DTBs from. No DT overlays are shipped, because the downstream overlays don't match the
  upstream DTBs.
- **Initramfs:** Fedora builds the SD card stack and filesystems as modules, so the
  initramfs adds `mmc_block sdhci sdhci-pltfm sdhci-brcmstb xfs erofs overlay`.
- **Updates:** rpi-bootc-bootloader copies each bootc deployment onto the FAT partition
  (`bootc/entries/ostree-N/`) and points the firmware's `os_prefix` at it, so `bootc upgrade`
  works with no bootloader.

## Build

### CI

CI ([`.github/workflows/build.yml`](.github/workflows/build.yml)) runs on a native arm64
runner. It only runs when started by hand:

```sh
gh workflow run build.yml --ref <branch>
gh run watch
gh run download <run-id> --name hummingbird-rpi5-unstable-sdcard-image
```

Each run uploads a compressed, flashable SD image
(`hummingbird-rpi5-unstable-<date>-<sha>.raw.xz`) as a workflow artifact, kept 14 days.
It also pushes the bootc image to `ghcr.io/<owner>/hummingbird-rpi5`:

| Tag | Pushed by | Use |
|---|---|---|
| `unstable-<date>-<sha>`, `unstable-<sha>` | every run, any branch | pin one exact build |
| `unstable` | runs on `main` only | what cards track for `bootc upgrade` |

There is no `latest` tag: it's reserved for a future stable channel. The image's
`org.opencontainers.image.version` label is `unstable-<date>-<sha>`, so `bootc status` shows
which build is running. The channel name is the `CHANNEL` variable in the workflow.

Older builds were pushed as `latest`, `<date>-<sha>` and `<sha>` before the switch to
`unstable` tags. `latest` is no longer updated and still points at an old build with the
AlmaLinux kernel, so don't track it.

### Locally

The SD image needs an arm64 host. On x86, the container image builds under qemu-user
emulation, but `bootc install` in `build-sd-image.sh` fails (`setns: Invalid argument`,
because qemu-user is multithreaded). Use CI or an arm64 machine.

On an arm64 host with podman (as root):

```sh
# 1. Build the bootc container image
sudo podman build -t localhost/hummingbird-rpi5:unstable -f Containerfile .

# 2. Assemble the SD card image
#    args: <local-image> <target-imgref for bootc upgrade> <output.raw> [size, default 8G]
sudo scripts/build-sd-image.sh \
  localhost/hummingbird-rpi5:unstable \
  ghcr.io/<owner>/hummingbird-rpi5:unstable \
  hummingbird-rpi5-unstable.raw

# 3. Optional: compress
xz -T0 hummingbird-rpi5-unstable.raw
```

## Flash and first boot

```sh
xzcat hummingbird-rpi5-unstable-*.raw.xz | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress
```

Before the first boot, mount the card's first partition (`CIDATA`) and put your SSH public
key in `user-data`. It has a `ssh-ed25519 REPLACE_WITH_YOUR_PUBLIC_KEY` placeholder under
`ssh_authorized_keys:`. This replaces the line after `ssh_authorized_keys:` and works for any
key type (adjust the key file and mount point):

```sh
KEY="$(cat ~/.ssh/<key>.pub)"
sed -i "/ssh_authorized_keys:/{n;s|.*|      - $KEY|}" /run/media/$USER/CIDATA/user-data
```

Boot with Ethernet connected, then find the Pi's IP:

- your router's client list (hostname `hummingbird-rpi`), or
- `nmap -sn <subnet>` (MAC vendor "Raspberry Pi Trading").

Then log in:

```sh
ssh -i ~/.ssh/<key> hummingbird@<ip>
```

Notes:

- After reflashing, SSH warns that the host key changed. Remove the old one with
  `ssh-keygen -R <ip>`.
- The first `bootc status` may print `mount: (hint) your fstab has been modified…`. It's
  harmless; `sudo systemctl daemon-reload` clears it.
- WiFi: `sudo nmcli dev wifi connect <ssid> password <password>`.
- Firmware settings go in `config-bootc-common.txt` on `CIDATA`. Don't edit `config.txt`:
  rpi-bootc-bootloader regenerates it on every sync.

The firmware partition (p1) isn't `/boot` (that's p2, XFS, read-only) and isn't mounted at
runtime. To read it:

```sh
sudo mkdir -p /mnt/p1 && sudo mount -o ro /dev/mmcblk0p1 /mnt/p1
# read files; they're root-only, so use sudo
sudo umount /mnt/p1
```

## Upgrades and rollback

`bootc upgrade` and `bootc switch` work. Staging a deployment triggers rpi-bootc-bootloader's
`ostree-finalize-staged` hook, which syncs the FAT partition at shutdown. A power cut during
an upgrade is untested.

`bootc upgrade` pulls the tag the card was built for, `:unstable` (only `main` moves it).
To run one specific build, for example from a branch, switch to its tag. A pinned tag never
moves, so `bootc upgrade` won't find anything newer until you switch back:

```sh
sudo bootc switch ghcr.io/<owner>/hummingbird-rpi5:unstable-<sha>   # pin one build
sudo bootc switch ghcr.io/<owner>/hummingbird-rpi5:unstable         # follow main again
```

Cards flashed before the switch to `unstable` tags track `:latest`, which is no longer
updated. Move them once with the second command above.

Automatic updates are off (`bootc-fetch-apply-updates.timer` is disabled), so a card only
changes when you run `bootc upgrade` or `bootc switch`.

### `bootc rollback` is not supported

With rpi-bootc-bootloader v0.0.8, `bootc rollback` stages nothing, so no sync runs. When the
two deployments have different kernels, ostree switches `/ostree/boot.N`, the FAT
`cmdline.txt` keeps a stale `ostree=/ostree/boot.N/…` path, and the Pi hangs at boot (solid
green LED, no network). Running `rpi-bootc-bootloader sync` afterwards fixes the paths, but
makes the *booted* deployment the default, so the rollback is ignored. This is being
reported upstream.

Verified way to roll back:

```sh
sudo rpi-bootc-bootloader sync        # default = booted, fallback/tryboot = the other one
sudo rpi-bootc-bootloader tryreboot   # boot the other deployment once
# now on the old deployment:
sudo rpi-bootc-bootloader sync        # make it the default
```

If the tryboot fails, a power cycle returns to the default. `tryreboot` needs `vcmailbox` in
the *currently booted* image. Holding the GPIO6 button (GPIO6 to GND, e.g. pin 31 to pin 39)
at power-on boots the fallback entry.

Gotcha: `vcmailbox 0x00038064 4 4 1` arms tryboot, so the next boot uses `tryboot.txt`. To
check that `vcmailbox` works, use a read-only tag such as `vcmailbox 0x00000001 4 4 0`
(firmware revision).

### Recovering a card that hangs after `bootc rollback`

On another machine:

1. Mount the root partition (p3) read-only. `sudo ls -l <root>/ostree/` shows which
   `boot.N` link exists (e.g. `boot.0 -> boot.0.1`). List the real deployment paths (the
   directory is root-only, so globs have to expand as root):
   `sudo find <root>/ostree/boot.0.1 -maxdepth 4 -printf '%p -> %l\n'`
2. Back up `bootc/entries/ostree-*/cmdline.txt` on the `CIDATA` partition, then fix `boot.N`
   in the `ostree=` path of each to match the path that exists.
3. Boot, then roll back with the tryboot method above.

## Known issues

- **Bluetooth address is the chip default** (`43:45:C0:00:1F:AC`), likely the same on every
  Pi 5. The upstream DTB has no `local-bd-address` for the firmware to fill in. Matters if
  you run more than one Pi near each other.
- **HDMI is untested.** `vc4` loads and logs an upstream `vc4-drm … late IOMMU probe` kernel
  WARNING, harmless so far.
- **Power button is untested.** The boot log shows
  `gpio-keys … Unable to get irq number for GPIO 0`.
- **`bootc rollback` isn't supported** (see above).
- **Stale files on the FAT partition.** rpi-bootc-bootloader never deletes files from an
  entry folder, so old DTBs and overlays stay after a kernel change.
- **Tainted kernel.** The unsigned `vcio.ko` and `8250_bcm7271.ko` taint the kernel (`O`/`E`).

> Thanks to [Claude](https://claude.ai) (Anthropic), which helped with guidance, reviews, script building and documentation edits.
