#!/usr/bin/env bash

build_xz() {
    echo "==> building xz and liblzma"
    (
        cd "$WORK_DIR/xz" || exit
        # One build gives the static liblzma, for bsdtar, and the xz that
        # links it. The LZMA Utils compatibility tools, xzdec, and the shell
        # scripts (xzgrep and friends) are left out. --enable-small trades a
        # little speed for a 15% smaller xz (and liblzma in bsdtar).
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --host="$AUTOCONF_HOST" \
            --prefix="$COMPRESSION_PREFIX" \
            --disable-shared \
            --enable-static \
            --disable-xzdec \
            --disable-lzmadec \
            --disable-lzmainfo \
            --disable-lzma-links \
            --disable-scripts \
            --disable-doc \
            --disable-nls \
            --enable-small \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make
        make -s install
        install_binary src/xz/xz xz
        # xz picks its mode from argv[0].
        make_link xz unxz
        make_link xz xzcat
    )
}
