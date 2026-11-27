#!/usr/bin/env bash

# age and age-keygen; not age-inspect or the batchpass plugin.
build_age() {
    echo "==> building age"
    local command
    for command in age age-keygen; do
        go_build age "./cmd/$command" "$command" \
            "-X main.Version=v$(source_version age)" || return 1
    done
}
