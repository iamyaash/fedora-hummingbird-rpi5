Hummingbird for Raspberry Pi 5 - UNSTABLE (native firmware boot, no UEFI)
==========================================================================

This is an experimental, unstable build. Expect breaking changes.

Before the first boot, edit user-data on this partition:
  - put your SSH public key under ssh_authorized_keys
    (replace the "ssh-ed25519 REPLACE_WITH_YOUR_PUBLIC_KEY" line)
  - optionally set a password (see the comments) for HDMI console login

Then boot the Pi with ethernet plugged in. Find its IP in your router's
client list (hostname: hummingbird-rpi) and log in:

  ssh -i <your-key> hummingbird@<ip>

Do not edit config.txt: rpi-bootc-bootloader regenerates it on every update.
Put firmware settings in config-bootc-common.txt instead. Don't add downstream
dtoverlay lines: the kernel uses upstream (Fedora) device trees, and no
overlays are shipped.

Don't use "bootc rollback": it can leave the Pi unable to boot. Roll back with
"rpi-bootc-bootloader sync", then "rpi-bootc-bootloader tryreboot", then
"rpi-bootc-bootloader sync" again. See the project README for details.
