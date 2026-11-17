#!/usr/bin/env bash

build_zstd() {
    echo "==> building zstd and libzstd"
    (
        cd "$WORK_DIR/zstd" || exit
        # Without the pre-1.0 (v0.1 to v0.7) frame formats, and without the
        # CLI's gzip, xz, and lz4 modes: pigz and xz are separate tools.
        local options=(CC="$CC" AR="$AR" RANLIB="$RANLIB" ZSTD_LEGACY_SUPPORT=0
            HAVE_ZLIB=0 HAVE_LZMA=0 HAVE_LZ4=0 BACKTRACE=0)
        run_make -C lib libzstd.a-mt "${options[@]}" CFLAGS="$STATIC_CFLAGS"
        make -s -C lib install-static install-includes \
            "${options[@]}" PREFIX="$COMPRESSION_PREFIX"
        # zstd-dll links the CLI against -lzstd, here the static library
        # just built, instead of compiling the library into it again. Like
        # upstream's zstd-frugal, the CLI has no benchmark (-b), dictionary
        # training (--train), or tracing: 15% of its size.
        run_make -C programs zstd-dll "${options[@]}" \
            CFLAGS="$STATIC_CFLAGS -DZSTD_NOBENCH -DZSTD_NODICT -DZSTD_NOTRACE" \
            LDFLAGS="$STATIC_LDFLAGS -L$COMPRESSION_PREFIX/lib"
        install_binary programs/zstd zstd
        # zstd picks its mode from argv[0].
        make_link zstd unzstd
        make_link zstd zstdcat
    )
}
