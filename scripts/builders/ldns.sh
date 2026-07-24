#!/usr/bin/env bash

build_ldns() {
    echo "==> building ldns/drill"
    (
        cd "$WORK_DIR/ldns" || exit
        CC="$CC" AR="$AR" RANLIB="$RANLIB" \
        CPPFLAGS="-I$DEPS_PREFIX/include" \
        LDFLAGS="$STATIC_LDFLAGS -L$DEPS_PREFIX/lib" \
        ./configure \
            --host="$ZIG_TARGET" \
            --disable-shared \
            --enable-static \
            --disable-dane \
            --disable-dane-verify \
            --disable-rpath \
            --with-drill \
            --with-ssl="$DEPS_PREFIX" \
            --without-pyldns \
            CFLAGS="$STATIC_CFLAGS"
        make -s -j"$JOBS"
        install_binary drill/drill drill
    )
}
