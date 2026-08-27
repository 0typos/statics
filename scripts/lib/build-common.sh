#!/usr/bin/env bash

export STATIC_CFLAGS='-Os -ffunction-sections -fdata-sections'
export STATIC_LDFLAGS='-static -Wl,--gc-sections -Wl,-s'

# Component builds run under one top-level GNU make jobserver (see
# scripts/build.sh), which enforces a single global parallelism budget across
# every component and its inner make. An explicit -j here would opt out of the
# jobserver and multiply the budget, so pass -j only when no jobserver exists
# (a builder invoked directly, outside the DAG).
run_make() {
    if [[ ${MAKEFLAGS-} == *jobserver* ]]; then
        make -s "$@"
    else
        make -s -j"$JOBS" "$@"
    fi
}

install_binary() {
    local source=$1
    local destination=$2
    install -m 0755 "$source" "$OUTPUT_DIR/$destination"
}

install_output_file() {
    local source=$1
    local destination=$2
    install -D -m 0644 "$source" "$OUTPUT_DIR/$destination"
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
