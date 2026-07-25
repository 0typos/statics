#!/usr/bin/env bash

build_rsync() {
    echo "==> building rsync"
    (
        cd "$WORK_DIR/rsync" || exit
        CC="$CC" AR="$AR" RANLIB="$RANLIB" PKG_CONFIG=false ./configure \
            --build="$(cc -dumpmachine)" \
            --host="$AUTOCONF_HOST" \
            --disable-debug \
            --disable-md2man \
            --disable-roll-simd \
            --disable-openssl \
            --disable-xxhash \
            --disable-zstd \
            --disable-lz4 \
            --disable-iconv \
            --disable-acl-support \
            --disable-xattr-support \
            --enable-ipv6 \
            --with-included-popt \
            --with-included-zlib \
            rsync_cv_HAVE_SOCKETPAIR=yes \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        make -s -j"$JOBS" rsync
        install_binary rsync rsync
    )
}
