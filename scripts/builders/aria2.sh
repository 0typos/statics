#!/usr/bin/env bash

build_expat() {
    echo "==> building expat (static, for aria2 and lftp)"
    (
        cd "$WORK_DIR/expat" || exit
        # The library only. It installs into its own tree, apart from
        # DEPS_PREFIX, so no other builder finds it by accident.
        CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" ./configure \
            --host="$AUTOCONF_HOST" \
            --prefix="$WORK_DIR/expat/install" \
            --disable-shared \
            --enable-static \
            --without-docbook \
            --without-examples \
            --without-tests \
            --without-xmlwf \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make -C lib
        make -s -C lib install
        make -s install-pkgconfigDATA
    )
}

build_aria2() {
    echo "==> building aria2"
    (
        cd "$WORK_DIR/aria2" || exit
        local expat=$WORK_DIR/expat/install
        # HTTP(S), FTP, BitTorrent, and Metalink (expat, not libxml2) with
        # OpenSSL and zlib. No GnuTLS, nettle, or libgcrypt, no SQLite
        # (Firefox and Chromium cookie stores), c-ares, libssh2 (SFTP), or
        # WebSocket RPC. --build makes every target a cross build.
        # aria2c -v prints __DATE__, which SOURCE_DATE_EPOCH fixes (as for
        # socat). -UNDEBUG keeps assert(), as upstream builds: Zig defines
        # NDEBUG when optimizing, and DHTBucket.cc adds nodes to a split
        # DHT bucket inside an assert().
        CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" ./configure \
            --build="$(cc -dumpmachine)" \
            --host="$AUTOCONF_HOST" \
            --prefix=/usr \
            --disable-nls \
            --disable-shared \
            --disable-websocket \
            --without-gnutls \
            --with-openssl \
            --without-libnettle \
            --without-libgmp \
            --without-libgcrypt \
            --without-libxml2 \
            --with-libexpat \
            --without-sqlite3 \
            --without-libcares \
            --with-libz \
            --without-libssh2 \
            --without-libuv \
            --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt \
            ARIA2_STATIC=yes \
            PKG_CONFIG_LIBDIR="$DEPS_PREFIX/lib/pkgconfig:$COMPRESSION_PREFIX/lib/pkgconfig:$expat/lib/pkgconfig" \
            CFLAGS="$STATIC_CFLAGS" \
            CXXFLAGS="$STATIC_CFLAGS -Wno-date-time -UNDEBUG" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make
        install_component_binary aria2 src/aria2c aria2c
    )
}
