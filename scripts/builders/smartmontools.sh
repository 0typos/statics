#!/usr/bin/env bash

build_smartmontools() {
    echo "==> building smartmontools (smartctl)"
    (
        cd "$WORK_DIR/smartmontools" || exit
        # C++ via the zig cxx wrapper (same as nmap); the drive database is
        # compiled in, so no runtime data files ship with the binary.
        CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" ./configure \
            --host="$AUTOCONF_HOST" \
            --disable-nls \
            CFLAGS="$STATIC_CFLAGS" \
            CXXFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make smartctl
        install_binary smartctl smartctl
    )
}
