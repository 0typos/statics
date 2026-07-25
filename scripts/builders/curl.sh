#!/usr/bin/env bash

build_curl() {
    echo "==> building curl"
    (
        cd "$WORK_DIR/curl" || exit
        CC="$CC" AR="$AR" RANLIB="$RANLIB" \
        PKG_CONFIG_LIBDIR="$DEPS_PREFIX/lib/pkgconfig" \
        CPPFLAGS="-I$DEPS_PREFIX/include" \
        LDFLAGS="$STATIC_LDFLAGS -L$DEPS_PREFIX/lib" \
        ./configure \
            --host="$AUTOCONF_HOST" \
            --disable-shared \
            --enable-static \
            --with-openssl="$DEPS_PREFIX" \
            --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt \
            --without-brotli \
            --without-gssapi \
            --without-libidn2 \
            --without-libpsl \
            --without-libssh2 \
            --without-nghttp2 \
            --without-nghttp3 \
            --without-quiche \
            --without-zlib \
            --without-zstd \
            --disable-docs \
            --disable-ldap \
            --disable-ldaps \
            --disable-manual \
            --disable-threaded-resolver \
            CFLAGS="$STATIC_CFLAGS"
        make -s -j"$JOBS"
        install_binary src/curl curl
    )
}
