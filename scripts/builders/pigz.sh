#!/usr/bin/env bash

build_pigz() {
    echo "==> building pigz"
    (
        cd "$WORK_DIR/pigz" || exit
        # Upstream's Makefile always links Zopfli for -11; NOZOPFLI drops it
        # (and its Apache-2.0 code), so the three sources compile directly.
        # shellcheck disable=SC2086  # flag lists
        "$CC" $STATIC_CFLAGS -DNOZOPFLI -I"$COMPRESSION_PREFIX/include" \
            pigz.c yarn.c try.c -o pigz \
            $STATIC_LDFLAGS -L"$COMPRESSION_PREFIX/lib" -lz -lpthread -lm
        install_binary pigz pigz
        # pigz decompresses when called unpigz.
        make_link pigz unpigz
    )
}
