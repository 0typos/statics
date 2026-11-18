#!/usr/bin/env bash

build_nethogs() {
    echo "==> building nethogs"
    (
        cd "$WORK_DIR/nethogs" || exit
        local ncurses=$WORK_DIR/ncurses/install
        # C++ with libpcap and the static ncurses from build_ncurses.
        # Upstream reads its version from git or the directory name.
        run_make -C src -f MakeApp.mk nethogs \
            VERSION="$(source_version nethogs)" \
            CC="$CC" CXX="$CXX" \
            CPPFLAGS="-I$DEPS_PREFIX/include -I$ncurses/include/ncurses -I$ncurses/include" \
            CFLAGS="$STATIC_CFLAGS" \
            CXXFLAGS="$STATIC_CFLAGS -std=c++14" \
            LDFLAGS="$STATIC_LDFLAGS -L$DEPS_PREFIX/lib -L$ncurses/lib"
        install_binary src/nethogs nethogs
    )
}
