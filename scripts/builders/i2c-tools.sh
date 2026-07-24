#!/usr/bin/env bash

build_i2c_tools() {
    echo "==> building i2c-tools"
    (
        cd "$WORK_DIR/i2c-tools" || exit
        make -s -j"$JOBS" \
            CC="$CC" \
            AR="$AR" \
            BUILD_DYNAMIC_LIB=0 \
            BUILD_STATIC_LIB=1 \
            USE_STATIC_LIB=1 \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS" \
            all-tools

        local program
        for program in i2cdetect i2cdump i2cget i2cset i2ctransfer; do
            install_binary "tools/$program" "$program"
        done
    )
}
