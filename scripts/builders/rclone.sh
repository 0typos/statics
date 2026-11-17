#!/usr/bin/env bash

# ./cmd/statics is the trimmed main from patches/go-mains/rclone/, which
# build.sh copies into the source tree; see docs/TOOLKIT.md for its contents.
build_rclone() {
    echo "==> building rclone"
    go_build rclone ./cmd/statics rclone \
        "-X github.com/rclone/rclone/fs.Version=v$(source_version rclone)"
}
