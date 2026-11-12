#!/usr/bin/env bash

# The same source as dropbearmulti's tunpipe program, as its own small binary
# for targets that do not want the whole multicall payload.
build_tunpipe() {
    echo "==> building standalone tunpipe"
    # shellcheck disable=SC2086  # flag lists split on purpose
    "$CC" -std=gnu11 $STATIC_CFLAGS -Dtunpipe_main=main \
        "$REPO_ROOT/tunpipe/tunpipe.c" \
        $STATIC_LDFLAGS -o "$WORK_DIR/tunpipe-standalone"
    install_binary "$WORK_DIR/tunpipe-standalone" tunpipe-standalone
}
