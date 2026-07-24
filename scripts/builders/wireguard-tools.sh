#!/usr/bin/env bash

build_wireguard_tools() {
    echo "==> building wireguard-tools/wg"
    (
        cd "$WORK_DIR/wireguard-tools" || exit
        make -C src -j"$JOBS" \
            CC="$CC" \
            LDFLAGS='-static -Wl,--gc-sections -Wl,-s' \
            wg
        install_binary src/wg wg
    )
}
