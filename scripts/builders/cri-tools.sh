#!/usr/bin/env bash

build_crictl() {
    echo "==> building crictl"
    go_build cri-tools ./cmd/crictl crictl \
        "-X sigs.k8s.io/cri-tools/pkg/version.Version=v$(source_version cri-tools)"
}
