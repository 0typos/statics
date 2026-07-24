#!/usr/bin/env bash

build_spi_tools() {
    echo "==> building spi-tools"
    (
        cd "$WORK_DIR/spi-tools" || exit
        cmake -S . -B build \
            -DCMAKE_BUILD_TYPE=MinSizeRel \
            -DCMAKE_SYSTEM_NAME=Linux \
            -DCMAKE_C_COMPILER="$CC" \
            -DCMAKE_EXE_LINKER_FLAGS="$STATIC_LDFLAGS"
        cmake --build build --parallel "$JOBS"
        install_binary build/spi-config spi-config
        install_binary build/spi-pipe spi-pipe
    )
}
