# Pinned base: bump the date tag and digest together.
ARG BASE_IMAGE=quay.io/hummingbird-community/os-minimal:20261028@sha256:712da83e76023496164d92c70d91658feb8703fbb1a5e4fc012cb0cf4a78056f

FROM ${BASE_IMAGE}

# GRUB and shim are protected by dnf in /etc/dnf/protected.d, so drop the protection so dnf can remove it
RUN rm -f /etc/dnf/protected.d/grub2-efi-aa64.conf \
          /etc/dnf/protected.d/grub2-tools-minimal.conf \
          /etc/dnf/protected.d/shim.conf

# Remove UEFI boot chain from dnf directly during build time
RUN dnf -y remove grub2-efi-aa64 grub2-tools grub2-tools-minimal grub2-common \
    shim-aa64 efibootmgr \
    && dnf clean all

RUN bootc container lint
