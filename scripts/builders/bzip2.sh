#!/usr/bin/env bash

build_bzip2() {
    echo "==> building bzip2"
    (
        cd "$WORK_DIR/bzip2" || exit
        # A plain Makefile; the command-line variables replace its -O2 -g.
        run_make libbz2.a bzip2 CC="$CC" AR="$AR" RANLIB="$RANLIB" \
            CFLAGS="$STATIC_CFLAGS -D_FILE_OFFSET_BITS=64" \
            LDFLAGS="$STATIC_LDFLAGS"
        install -D -m 0644 libbz2.a "$COMPRESSION_PREFIX/lib/libbz2.a"
        install -D -m 0644 bzlib.h "$COMPRESSION_PREFIX/include/bzlib.h"
        install_binary bzip2 bzip2
        # bzip2 picks its mode from argv[0], as upstream's install does.
        make_link bzip2 bunzip2
        make_link bzip2 bzcat
    )
}
