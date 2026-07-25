#!/usr/bin/env bash

build_iperf3() {
    echo "==> building iperf3"
    (
        cd "$WORK_DIR/iperf3" || exit
        CC="$CC" AR="$AR" RANLIB="$RANLIB" \
        CPPFLAGS="-I$DEPS_PREFIX/include" \
        LDFLAGS="$STATIC_LDFLAGS -L$DEPS_PREFIX/lib" \
        ./configure \
            --host="$AUTOCONF_HOST" \
            --disable-shared \
            --enable-static \
            --enable-static-bin \
            --without-sctp \
            --with-openssl="$DEPS_PREFIX" \
            CFLAGS="$STATIC_CFLAGS"
        make -s -j"$JOBS"
        install_binary src/iperf3 iperf3
    )
}
