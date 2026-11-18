#!/usr/bin/env bash

build_dhcpdump() {
    echo "==> building dhcpdump"
    (
        cd "$WORK_DIR/dhcpdump" || exit
        patch -s -p1 < "$REPO_ROOT/patches/dhcpdump-numeric-ports.patch"
        # NO_TUI drops the interactive session tracker (-t) and its yascreen
        # dependency; the packet dump itself is unchanged. The Makefile adds
        # its own flags, including -O3, after CFLAGS from the environment;
        # LDFLAGS on the command line replaces its PIE link.
        CFLAGS="$STATIC_CFLAGS" CPPFLAGS="-I$DEPS_PREFIX/include" \
        PKG_CONFIG_LIBDIR="$DEPS_PREFIX/lib/pkgconfig" \
        run_make dhcpdump NO_TUI=1 CC="$CC" \
            LDFLAGS="$STATIC_LDFLAGS -L$DEPS_PREFIX/lib"
        install_binary dhcpdump dhcpdump
    )
}
