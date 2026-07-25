#!/usr/bin/env bash

build_lsof() {
    echo "==> building lsof"
    (
        cd "$WORK_DIR/lsof" || exit
        CC="$CC" AR="$AR" RANLIB="$RANLIB" PKG_CONFIG=false ./configure \
            --build="$(cc -dumpmachine)" \
            --host="$AUTOCONF_HOST" \
            --disable-shared \
            --enable-static \
            --disable-liblsof \
            --without-libtirpc \
            --without-selinux \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        make -s -j"$JOBS" lsof
        install_binary lsof lsof
    )
}
