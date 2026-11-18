#!/usr/bin/env bash

build_microsocks() {
    echo "==> building microsocks"
    (
        cd "$WORK_DIR/microsocks" || exit
        run_make CC="$CC" CFLAGS="$STATIC_CFLAGS" LDFLAGS="$STATIC_LDFLAGS"
        install_binary microsocks microsocks
    )
}
