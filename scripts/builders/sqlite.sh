#!/usr/bin/env bash

build_sqlite() {
    echo "==> building sqlite"
    (
        cd "$WORK_DIR/sqlite" || exit
        local ncurses=$WORK_DIR/ncurses/install readline=$WORK_DIR/readline/install
        # The sqlite3 shell with the library compiled in, from the autoconf
        # amalgamation. --all adds FTS4, FTS5, R-Tree, Geopoly, sessions,
        # carray, and the dbpage and dbstat tables (.recover needs dbpage)
        # to the default JSON and math functions. No loadable extensions: a static
        # program cannot dlopen. Line editing is the static readline on the
        # static ncurses. No zlib, so no .archive or zipfile. autosetup
        # builds its own Tcl (jimsh) with the host cc and runs no target
        # program.
        ./configure \
            --build="$(cc -dumpmachine)" \
            --host="$AUTOCONF_HOST" \
            --disable-shared \
            --disable-load-extension \
            --all \
            --with-readline-cflags="-I$readline/include" \
            --with-readline-ldflags="-L$readline/lib -L$ncurses/lib -lreadline -lncurses" \
            CC="$CC" \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make sqlite3
        install_component_binary sqlite sqlite3 sqlite3
        # The archive has no license file: SQLite is in the public domain,
        # and each source file opens with this blessing instead.
        awk '/The author disclaims copyright/ { on = 1 }
            on { print }
            on && /May you share freely/ { exit }' sqlite3.c > SQLITE-BLESSING
        grep -q 'May you share freely' SQLITE-BLESSING || {
            echo "SQLITE-BLESSING lacks sqlite3.c's blessing" >&2
            exit 1
        }
    )
}
