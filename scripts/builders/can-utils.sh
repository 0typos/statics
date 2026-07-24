#!/usr/bin/env bash

build_can_utils() {
    echo "==> building can-utils"
    (
        cd "$WORK_DIR/can-utils" || exit
        make -s -j"$JOBS" \
            CC="$CC" \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS" \
            candump cansend cangen canplayer cansniffer \
            isotpdump isotprecv isotpsend slcand canbusload

        local program
        for program in candump cansend cangen canplayer cansniffer \
            isotpdump isotprecv isotpsend slcand canbusload; do
            install_binary "$program" "$program"
        done
    )
}
