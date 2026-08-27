#!/usr/bin/env bash

build_socat() {
    echo "==> building socat"
    (
        cd "$WORK_DIR/socat" || exit
        CC="$CC" \
        CPPFLAGS="-I$DEPS_PREFIX/include" \
        LDFLAGS="-static -Wl,--gc-sections -Wl,-s -L$DEPS_PREFIX/lib" \
        ./configure \
            --host="$AUTOCONF_HOST" \
            --enable-openssl \
            --enable-openssl-base="$DEPS_PREFIX" \
            --disable-readline \
            CFLAGS='-Os -Wno-date-time'
        run_make
        install_binary socat socat
    )
}
