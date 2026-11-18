#!/usr/bin/env bash

build_iftop() {
    echo "==> building iftop"
    (
        cd "$WORK_DIR/iftop" || exit
        local ncurses=$WORK_DIR/ncurses/install
        # Its 2014 config.sub predates riscv64; take the builder's automake
        # copies.
        cp "$(automake --print-libdir)"/config.sub "$(automake --print-libdir)"/config.guess config/
        # libpcap and the static ncurses from build_ncurses; reverse lookups
        # with gethostbyaddr_r on a resolver thread. Its headers define
        # globals that several files include: -fcommon, as before GCC 10.
        CC="$CC" ./configure \
            --host="$AUTOCONF_HOST" \
            --with-resolver=netdb \
            --with-libpcap="$DEPS_PREFIX" \
            CPPFLAGS="-I$DEPS_PREFIX/include -I$ncurses/include/ncurses -I$ncurses/include" \
            CFLAGS="$STATIC_CFLAGS -fcommon" \
            LDFLAGS="$STATIC_LDFLAGS -L$DEPS_PREFIX/lib -L$ncurses/lib"
        run_make
        install_binary iftop iftop
    )
}
