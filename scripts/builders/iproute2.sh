#!/usr/bin/env bash

build_iproute2() {
    echo "==> building iproute2 (ip, ss, bridge, tc)"
    (
        cd "$WORK_DIR/iproute2" || exit
        CC="$CC" AR="$AR" \
        PKG_CONFIG_LIBDIR="$DEPS_PREFIX/lib/pkgconfig" \
        ./configure
        make -j"$JOBS" \
            SUBDIRS='lib ip bridge misc tc' \
            SHARED_LIBS=n \
            CC="$CC" \
            AR="$AR" \
            LDFLAGS="-static -Wl,--gc-sections -Wl,-s -L$DEPS_PREFIX/lib"
        install_binary ip/ip ip
        install_binary bridge/bridge bridge
        install_binary misc/ss ss
        install_binary tc/tc tc
    )
}
