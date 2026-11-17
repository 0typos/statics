#!/usr/bin/env bash

build_mbuffer() {
    echo "==> building mbuffer"
    (
        cd "$WORK_DIR/mbuffer" || exit
        # --md5 would need libmd or OpenSSL's libcrypto.
        CC="$CC" ./configure \
            --host="$AUTOCONF_HOST" \
            --disable-debug \
            --disable-md5 \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make mbuffer
        install_binary mbuffer mbuffer
    )
}
