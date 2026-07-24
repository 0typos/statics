#!/usr/bin/env bash

export STATIC_CFLAGS='-Os -ffunction-sections -fdata-sections'
export STATIC_LDFLAGS='-static -Wl,--gc-sections -Wl,-s'

install_binary() {
    local source=$1
    local destination=$2
    install -m 0755 "$source" "$OUTPUT_DIR/$destination"
}

install_dependency_file() {
    local source=$1
    local destination=$2
    install -D -m 0644 "$source" "$DEPS_PREFIX/$destination"
}

make_link() {
    local target=$1
    local link_name=$2
    ln -s "$target" "$OUTPUT_DIR/$link_name"
}
