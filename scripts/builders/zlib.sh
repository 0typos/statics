#!/usr/bin/env bash

build_zlib() {
    echo "==> building zlib"
    (
        cd "$WORK_DIR/zlib" || exit
        # zlib's own configure, not autoconf: it reads CHOST for the target.
        # The s390x CRC32-VX path fails under zig cc without -fzvector and
        # targets z13 anyway (as for Nmap's bundled copy).
        CHOST="$AUTOCONF_HOST" CC="$CC" AR="$AR" RANLIB="$RANLIB" \
            CFLAGS="$STATIC_CFLAGS" ./configure \
            --static \
            --disable-crcvx \
            --prefix="$COMPRESSION_PREFIX"
        run_make libz.a
        make -s install
    )
}
