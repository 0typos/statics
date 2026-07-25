#!/usr/bin/env bash

build_mtr() {
    echo "==> building mtr"
    (
        cd "$WORK_DIR/mtr" || exit
        ./bootstrap.sh
        CC="$CC" PKG_CONFIG=false ./configure \
            --host="$AUTOCONF_HOST" \
            --without-gtk \
            --without-ipinfo \
            --without-jansson \
            --without-ncurses \
            --without-ncursesw \
            --disable-bash-completion \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        make -s -j"$JOBS" mtr mtr-packet
        install_binary mtr mtr
        install_binary mtr-packet mtr-packet
    )
}
