#!/usr/bin/env bash

build_picocom() {
    echo "==> building picocom"
    (
        cd "$WORK_DIR/picocom" || exit
        # Arbitrary (non-B*) baud rates use a glibc-only termios2 shim that
        # upstream enables on x86 alone; musl lacks the fields it touches.
        # Every target gets the standard rates, up to 4 Mbaud (HIGH_BAUD).
        # Command-line CFLAGS and LDFLAGS also drop the Makefile's -g.
        run_make picocom CC="$CC" \
            CFLAGS="$STATIC_CFLAGS -DNO_CUSTOM_BAUD" \
            LDFLAGS="$STATIC_LDFLAGS"
        install_binary picocom picocom
    )
}
