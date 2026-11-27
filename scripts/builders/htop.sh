#!/usr/bin/env bash

build_htop() {
    echo "==> building htop"
    (
        cd "$WORK_DIR/htop" || exit
        local ncurses=$WORK_DIR/ncurses/install
        # The static narrow-character ncurses from build_ncurses, so no
        # Unicode meters or tree lines. No libsensors, libcap, libnl delay
        # accounting, hwloc, or backtraces; CPU affinity uses the
        # sched_setaffinity calls directly.
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --build="$(cc -dumpmachine)" \
            --host="$AUTOCONF_HOST" \
            --enable-static \
            --disable-unicode \
            --enable-affinity \
            --disable-hwloc \
            --disable-sensors \
            --disable-capabilities \
            --disable-delayacct \
            --disable-backtrace \
            --without-libunwind \
            --with-curses=ncurses \
            PKG_CONFIG=false \
            CPPFLAGS="-I$ncurses/include/ncurses -I$ncurses/include" \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS -L$ncurses/lib"
        run_make
        install_component_binary htop htop htop
    )
}
