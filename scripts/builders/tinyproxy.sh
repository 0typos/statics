#!/usr/bin/env bash

build_tinyproxy() {
    echo "==> building tinyproxy"
    (
        cd "$WORK_DIR/tinyproxy" || exit
        # Upstream's defaults (filtering, upstream, reverse, and
        # transparent proxying) cost little. No manual pages.
        CC="$CC" ./configure \
            --host="$AUTOCONF_HOST" \
            --prefix=/usr \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --disable-manpage_support \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make -C src tinyproxy
        install_binary src/tinyproxy tinyproxy
        # hsearch.c is musl's, under the MIT license in its header.
        awk '/^#/ { exit } { print }' src/hsearch.c > TINYPROXY-NOTICES
        grep -q 'Permission is hereby granted' TINYPROXY-NOTICES || {
            echo "TINYPROXY-NOTICES lacks hsearch.c's notice" >&2
            exit 1
        }
    )
}
