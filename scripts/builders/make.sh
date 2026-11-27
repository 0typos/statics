#!/usr/bin/env bash

build_make() {
    echo "==> building make"
    (
        cd "$WORK_DIR/make" || exit
        # GNU make without Guile, NLS, or `load` (a static program cannot
        # dlopen). --build makes every target a cross build.
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --build="$(cc -dumpmachine)" \
            --host="$AUTOCONF_HOST" \
            --without-guile \
            --disable-nls \
            --disable-load \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make
        install_component_binary make make make
    )
}
