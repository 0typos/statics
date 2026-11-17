#!/usr/bin/env bash

# ctr only. containerd's build tags (no_btrfs, no_devmapper, no_zfs, no_cri,
# no_rdt, no_systemd, no_tracing) select daemon plugins that ctr does not
# link, so none of them changes its size; no_grpc does not build.
build_ctr() {
    echo "==> building ctr"
    go_build containerd ./cmd/ctr ctr \
        "-X github.com/containerd/containerd/v2/version.Version=v$(source_version containerd)"
}
