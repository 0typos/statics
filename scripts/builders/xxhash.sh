#!/usr/bin/env bash

build_xxhash() {
    echo "==> building xxhsum and libxxhash"
    (
        cd "$WORK_DIR/xxhash" || exit
        # The scalar and SSE2/NEON code paths only: DISPATCH=0 leaves out
        # the AVX2 and AVX-512 variants and the CPU dispatcher on x86.
        # libxxhash.a, from the same build, is linked into partclone.
        local options=(CC="$CC" AR="$AR" DISPATCH=0
            CFLAGS="$STATIC_CFLAGS" LDFLAGS="$STATIC_LDFLAGS")
        run_make xxhsum libxxhash.a "${options[@]}"
        install_binary xxhsum xxhsum
    )
}
