#!/usr/bin/env bash

# libnftnl builds on the libmnl already produced by build_dependencies, and nft
# links both. mini-gmp is bundled (no libgmp), --without-cli drops the readline
# dependency, and JSON/xtables stay off to keep the static binary compact.

build_libnftnl() {
    echo "==> building libnftnl"
    (
        cd "$WORK_DIR/libnftnl" || exit
        CC="$CC" AR="$AR" RANLIB="$RANLIB" \
        PKG_CONFIG_LIBDIR="$DEPS_PREFIX/lib/pkgconfig" \
        LIBMNL_CFLAGS="-I$DEPS_PREFIX/include" \
        LIBMNL_LIBS="-L$DEPS_PREFIX/lib -lmnl" \
        ./configure \
            --host="$AUTOCONF_HOST" \
            --prefix="$DEPS_PREFIX" \
            --disable-shared \
            --enable-static \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        make -s -j"$JOBS"
        make -s install
    )
}

build_nftables() {
    echo "==> building nftables (nft)"
    (
        cd "$WORK_DIR/nftables" || exit
        CC="$CC" AR="$AR" RANLIB="$RANLIB" \
        PKG_CONFIG_LIBDIR="$DEPS_PREFIX/lib/pkgconfig" \
        LIBMNL_CFLAGS="-I$DEPS_PREFIX/include" \
        LIBMNL_LIBS="-L$DEPS_PREFIX/lib -lmnl" \
        LIBNFTNL_CFLAGS="-I$DEPS_PREFIX/include" \
        LIBNFTNL_LIBS="-L$DEPS_PREFIX/lib -lnftnl -lmnl" \
        ./configure \
            --host="$AUTOCONF_HOST" \
            --prefix="$DEPS_PREFIX" \
            --disable-shared \
            --enable-static \
            --without-cli \
            --with-mini-gmp \
            --without-xtables \
            --disable-man-doc \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS -L$DEPS_PREFIX/lib"
        # nftables bakes `date +%s` into nftbuildstamp[] (configure.ac
        # MAKE_STAMP); pin it to SOURCE_DATE_EPOCH so two builds match.
        make -s -j"$JOBS" MAKE_STAMP="$SOURCE_DATE_EPOCH"
        install_binary src/nft nft
    )
}
