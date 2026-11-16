#!/usr/bin/env bash

build_lrzsz() {
    echo "==> building lrzsz"
    (
        cd "$WORK_DIR/lrzsz" || exit
        # -Werror is upstream's default and turns Zig's newer clang warnings
        # into failures; NLS would need a target libintl.
        CC="$CC" ./configure \
            --host="$AUTOCONF_HOST" \
            --disable-nls \
            --disable-Werror \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make -C src lrz lsz
        # Installed under the names users type; both check argv[0] only for
        # an optional leading "r" or "-" (restricted mode, login shell).
        install_binary src/lsz sz
        install_binary src/lrz rz
    )
}
