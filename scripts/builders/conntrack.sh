#!/usr/bin/env bash

# conntrack links libnetfilter_conntrack, libnfnetlink, and the libmnl from
# build_dependencies. Only the conntrack CLI is built: no conntrackd, nfct,
# or user-space helpers.

build_libnfnetlink() {
    echo "==> building libnfnetlink"
    (
        cd "$WORK_DIR/libnfnetlink" || exit
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --host="$AUTOCONF_HOST" \
            --prefix="$DEPS_PREFIX" \
            --disable-shared \
            --enable-static \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make
        make -s install
    )
}

build_libnetfilter_conntrack() {
    echo "==> building libnetfilter_conntrack"
    (
        cd "$WORK_DIR/libnetfilter_conntrack" || exit
        CC="$CC" AR="$AR" RANLIB="$RANLIB" \
        PKG_CONFIG_LIBDIR="$DEPS_PREFIX/lib/pkgconfig" \
        ./configure \
            --host="$AUTOCONF_HOST" \
            --prefix="$DEPS_PREFIX" \
            --disable-shared \
            --enable-static \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make
        make -s install
    )
}

build_conntrack() {
    echo "==> building conntrack-tools (conntrack)"
    (
        cd "$WORK_DIR/conntrack-tools" || exit
        # musl has no Sun RPC headers and configure then demands libtirpc.
        # Only the user-space helpers (--disable-cthelper) include them.
        ac_cv_header_rpc_rpc_msg_h=yes \
        CC="$CC" AR="$AR" RANLIB="$RANLIB" \
        PKG_CONFIG_LIBDIR="$DEPS_PREFIX/lib/pkgconfig" \
        ./configure \
            --host="$AUTOCONF_HOST" \
            --disable-cthelper \
            --disable-cttimeout \
            --disable-systemd \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make -C extensions
        run_make -C src conntrack
        install_binary src/conntrack conntrack
    )
}
