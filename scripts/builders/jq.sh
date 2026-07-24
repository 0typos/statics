#!/usr/bin/env bash

build_jq() {
    echo "==> building jq"
    (
        cd "$WORK_DIR/jq" || exit
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --host="$ZIG_TARGET" \
            --disable-shared \
            --enable-static \
            --enable-all-static \
            --disable-docs \
            --with-oniguruma=builtin \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        make -s -j"$JOBS"
        install_binary jq jq
    )
}
