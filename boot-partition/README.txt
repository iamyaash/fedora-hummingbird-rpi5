Fedora Hummingbird for Raspberry Pi 5 (native firmware boot, no UEFI)
=====================================================================

Before the first boot, edit user-data on this partition:
  - put your SSH public key under ssh_authorized_keys
  - optionally set a password (see the comments) for HDMI console login

Then boot the Pi with ethernet plugged in. Find its IP in your router's
client list (hostname: hummingbird-rpi) and log in:

  ssh hummingbird@<ip>

Do not edit config.txt: rpi-bootc-bootloader regenerates it on every update.
Put firmware settings in config-bootc-common.txt instead.
