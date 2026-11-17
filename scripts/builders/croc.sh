#!/usr/bin/env bash

# components.tsv builds croc with upstream's croc_no_tailcat tag: relay-only
# transfers, without the Tailscale-based DERP transport and `croc ssh`.
build_croc() {
    echo "==> building croc"
    go_build croc . croc
}
