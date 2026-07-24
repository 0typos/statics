#!/usr/bin/env bash

build_socat() {
    echo "==> building socat"
    (
        cd "$WORK_DIR/socat" || exit
        CC="$CC" ./configure \
            --host="$ZIG_TARGET" \
            --disable-openssl \
            --disable-readline \
            CFLAGS='-Os -Wno-date-time' \
            LDFLAGS='-static -Wl,--gc-sections -Wl,-s'
        make -s -j"$JOBS"
        install_binary socat socat
    )
}
