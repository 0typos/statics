#!/usr/bin/env bash

build_udpcast() {
    echo "==> building udpcast (udp-sender and udp-receiver)"
    (
        cd "$WORK_DIR/udpcast" || exit
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --build="$(cc -dumpmachine)" \
            --host="$AUTOCONF_HOST" \
            --prefix=/usr \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make udp-sender udp-receiver
        install_binary udp-sender udp-sender
        install_binary udp-receiver udp-receiver
    )
}
