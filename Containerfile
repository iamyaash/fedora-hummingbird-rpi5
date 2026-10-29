# Pinned base: bump the date tag and digest together.
ARG BASE_IMAGE=quay.io/hummingbird-community/os-minimal:20261028@sha256:712da83e76023496164d92c70d91658feb8703fbb1a5e4fc012cb0cf4a78056f

FROM ${BASE_IMAGE}

RUN bootc container lint
