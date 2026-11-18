#!/usr/bin/env bash

build_libevent() {
    echo "==> building libevent (static libevent_core for tmux)"
    (
        cd "$WORK_DIR/libevent" || exit
        # Only libevent_core is linked: no OpenSSL bufferevents, no
        # threading, no debug mode. It installs into its own tree, apart
        # from DEPS_PREFIX, so no other builder finds it by accident.
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --host="$AUTOCONF_HOST" \
            --prefix="$WORK_DIR/libevent/install" \
            --disable-shared \
            --enable-static \
            --enable-function-sections \
            --disable-openssl \
            --disable-thread-support \
            --disable-debug-mode \
            --disable-libevent-regress \
            --disable-samples \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make
        make -s install
    )
}

build_tmux() {
    echo "==> building tmux"
    (
        cd "$WORK_DIR/tmux" || exit
        local libevent=$WORK_DIR/libevent/install
        local ncurses=$WORK_DIR/ncurses/install
        # libevent_core from build_libevent and the static ncurses from
        # build_ncurses, whose compiled-in terminal descriptions include
        # tmux, tmux-256color, screen, and xterm-256color. No utempter,
        # utf8proc, systemd, sixel, or jemalloc. Both libraries are found
        # through pkg-config's own static .pc for libevent and plain -l
        # for ncurses, which ships no .pc in its narrow build. --build makes
        # every target a cross build, so configure's run-time probes take
        # the same answers on x86_64 as elsewhere. Panes get TERM=screen,
        # the description a target's own programs are likeliest to know.
        CC="$CC" ./configure \
            --build="$(cc -dumpmachine)" \
            --host="$AUTOCONF_HOST" \
            --prefix=/usr \
            --with-TERM=screen \
            --disable-utempter \
            --disable-utf8proc \
            --disable-systemd \
            --disable-sixel \
            --disable-jemalloc \
            PKG_CONFIG_LIBDIR="$libevent/lib/pkgconfig" \
            CPPFLAGS="-I$ncurses/include/ncurses -I$ncurses/include" \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS -L$ncurses/lib"
        run_make
        install_binary tmux tmux
        # tmux's own files are ISC; xmalloc.c (Tatu Ylonen's SSH-short
        # grant), the compat replacements it compiled for musl, and the BSD
        # queue.h and tree.h it uses carry their own notices in the
        # comments before their first directive.
        local file
        for file in xmalloc.c compat/queue.h compat/tree.h $(
            find compat -name '*.o' | sed 's/\.o$/.c/' | LC_ALL=C sort
        ); do
            echo "$file:"
            awk '/^#/ { exit } { print }' "$file"
        done > TMUX-NOTICES
        if ! grep -q 'The NetBSD Foundation' TMUX-NOTICES ||
            ! grep -q 'can be used freely for any purpose' TMUX-NOTICES; then
            echo "TMUX-NOTICES lacks the compat notices" >&2
            exit 1
        fi
        # base64.c's IBM grant, which has no SPDX identifier, on its own
        # for the SBOM (LicenseRef-IBM-base64).
        sed -n '/Portions Copyright (c) 1995 by International Business Machines/,/\*\//p' \
            compat/base64.c > IBM-BASE64
        grep -q 'IBM DISCLAIMS ALL WARRANTIES' IBM-BASE64 || {
            echo "IBM-BASE64 lacks base64.c's IBM notice" >&2
            exit 1
        }
    )
}
