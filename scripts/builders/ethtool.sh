#!/usr/bin/env bash

build_ethtool() {
    echo "==> building ethtool"
    (
        cd "$WORK_DIR/ethtool" || exit
        CC="$CC" \
        PKG_CONFIG_LIBDIR="$DEPS_PREFIX/lib/pkgconfig" \
        MNL_CFLAGS="-I$DEPS_PREFIX/include" \
        MNL_LIBS="$DEPS_PREFIX/lib/libmnl.a" \
        ./configure \
            --host="$ZIG_TARGET" \
            --enable-netlink \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        make -s -j"$JOBS"
        install_binary ethtool ethtool
    )
}
