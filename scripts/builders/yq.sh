#!/usr/bin/env bash

build_yq() {
    echo "==> building yq"
    go_build yq . yq
}
