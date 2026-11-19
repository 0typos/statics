#!/usr/bin/env bash

build_libssh2() {
    echo "==> building libssh2 (static, for curl's sftp:// and scp://)"
    (
        cd "$WORK_DIR/libssh2" || exit
        # The pinned OpenSSL for its crypto and zlib for SSH compression.
        # It installs into its own tree, apart from DEPS_PREFIX, so no other
        # builder finds it by accident.
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --host="$AUTOCONF_HOST" \
            --prefix="$WORK_DIR/libssh2/install" \
            --disable-shared \
            --enable-static \
            --disable-examples-build \
            --disable-docker-tests \
            --disable-sshd-tests \
            --with-crypto=openssl \
            --with-libssl-prefix="$DEPS_PREFIX" \
            --with-libz \
            CPPFLAGS="-I$COMPRESSION_PREFIX/include" \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS -L$COMPRESSION_PREFIX/lib"
        run_make -C src
        make -s -C src install
        make -s install-pkgconfigDATA install-includeHEADERS
    )
}

build_curl() {
    echo "==> building curl"
    (
        cd "$WORK_DIR/curl" || exit
        # libssh2 adds sftp:// and scp://; the zlib it links also gives
        # --compressed.
        CC="$CC" AR="$AR" RANLIB="$RANLIB" \
        PKG_CONFIG_LIBDIR="$DEPS_PREFIX/lib/pkgconfig:$WORK_DIR/libssh2/install/lib/pkgconfig:$COMPRESSION_PREFIX/lib/pkgconfig" \
        CPPFLAGS="-I$DEPS_PREFIX/include" \
        LDFLAGS="$STATIC_LDFLAGS -L$DEPS_PREFIX/lib" \
        ./configure \
            --host="$AUTOCONF_HOST" \
            --disable-shared \
            --enable-static \
            --with-openssl="$DEPS_PREFIX" \
            --with-libssh2="$WORK_DIR/libssh2/install" \
            --with-zlib="$COMPRESSION_PREFIX" \
            --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt \
            --without-brotli \
            --without-gssapi \
            --without-libidn2 \
            --without-libpsl \
            --without-nghttp2 \
            --without-nghttp3 \
            --without-quiche \
            --without-zstd \
            --disable-docs \
            --disable-ldap \
            --disable-ldaps \
            --disable-manual \
            --disable-threaded-resolver \
            CFLAGS="$STATIC_CFLAGS"
        grep -q '^#define USE_LIBSSH2 1' lib/curl_config.h || {
            echo "curl configured without libssh2" >&2
            exit 1
        }
        run_make
        install_binary src/curl curl
    )
}
