#!/usr/bin/env bash

build_ipset() {
    echo "==> building ipset"
    (
        cd "$WORK_DIR/ipset" || exit
        # Userspace only, linking libmnl. Every set type is compiled into
        # libipset rather than loaded as a module.
        CC="$CC" AR="$AR" RANLIB="$RANLIB" \
        PKG_CONFIG_LIBDIR="$DEPS_PREFIX/lib/pkgconfig" \
        ./configure \
            --host="$AUTOCONF_HOST" \
            --with-kmod=no \
            --disable-shared \
            --enable-static \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS -L$DEPS_PREFIX/lib"
        run_make
        install_binary src/ipset ipset
    )
}
