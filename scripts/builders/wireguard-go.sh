#!/usr/bin/env bash

build_wireguard_go() {
    echo "==> building wireguard-go"
    go_build wireguard-go . wireguard-go
}
