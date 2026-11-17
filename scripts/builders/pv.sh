#!/usr/bin/env bash

build_pv() {
    echo "==> building pv"
    (
        cd "$WORK_DIR/pv" || exit
        # Without ncurses pv uses fixed terminal sequences; NLS would need a
        # target libintl.
        CC="$CC" ./configure \
            --host="$AUTOCONF_HOST" \
            --disable-nls \
            --without-ncurses \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make pv
        install_binary pv pv
    )
}
