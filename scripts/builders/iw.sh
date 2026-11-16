#!/usr/bin/env bash

build_libnl() {
    echo "==> building libnl"
    (
        cd "$WORK_DIR/libnl" || exit
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --host="$AUTOCONF_HOST" \
            --prefix="$DEPS_PREFIX" \
            --disable-shared \
            --enable-static \
            --enable-cli=no \
            --disable-debug \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make
        make -s install
    )
}

build_iw() {
    echo "==> building iw"
    (
        cd "$WORK_DIR/iw" || exit
        # iw finds libnl through pkg-config; only the pinned static build.
        export PKG_CONFIG_LIBDIR="$DEPS_PREFIX/lib/pkgconfig"
        # From the environment, so the Makefile still appends its own flags.
        # No --gc-sections: iw finds its command table through
        # __start___cmd/__stop___cmd, and LLD collects those sections. Zig's
        # linker driver rejects the -z nostart-stop-gc that would keep them.
        CFLAGS="$STATIC_CFLAGS" LDFLAGS='-static -Wl,-s' run_make CC="$CC"
        install_binary iw iw
    )
}
