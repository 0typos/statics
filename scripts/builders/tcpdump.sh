#!/usr/bin/env bash

build_tcpdump() {
    echo "==> building tcpdump"
    (
        cd "$WORK_DIR/tcpdump" || exit
        CC="$CC" AR="$AR" RANLIB="$RANLIB" \
        PKG_CONFIG_LIBDIR="$DEPS_PREFIX/lib/pkgconfig" \
        CPPFLAGS="-I$DEPS_PREFIX/include" \
        ./configure \
            --host="$AUTOCONF_HOST" \
            --disable-local-libpcap \
            --without-cap-ng \
            --without-crypto \
            --without-smi \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS -L$DEPS_PREFIX/lib"
        make -s -j"$JOBS"
        install_binary tcpdump tcpdump
    )
}
