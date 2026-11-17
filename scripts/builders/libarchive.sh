#!/usr/bin/env bash

build_libarchive() {
    echo "==> building libarchive (bsdtar, bsdcpio)"
    (
        cd "$WORK_DIR/libarchive" || exit
        # Every format libarchive reads or writes without an extra library,
        # with gzip, bzip2, xz/lzma, and zstd from the libraries built here.
        # No crypto library (AES-encrypted zip and 7z, mtree and xar digests),
        # no libxml2 or expat (xar), no lz4, lzo, iconv, or ACLs.
        CC="$CC" AR="$AR" RANLIB="$RANLIB" PKG_CONFIG=false ./configure \
            --host="$AUTOCONF_HOST" \
            --disable-shared \
            --enable-static \
            --enable-bsdtar=static \
            --enable-bsdcpio=static \
            --disable-bsdcat \
            --disable-bsdunzip \
            --disable-acl \
            --enable-posix-regex-lib=libc \
            --with-zlib \
            --with-bz2lib \
            --with-lzma \
            --with-zstd \
            --without-libb2 \
            --without-iconv \
            --without-lz4 \
            --without-lzo2 \
            --without-cng \
            --without-mbedtls \
            --without-nettle \
            --without-openssl \
            --without-xml2 \
            --without-expat \
            CPPFLAGS="-I$COMPRESSION_PREFIX/include" \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS -L$COMPRESSION_PREFIX/lib"
        run_make bsdtar bsdcpio
        install_binary bsdtar bsdtar
        install_binary bsdcpio bsdcpio
        # COPYING defers to these two files for their UC Regents notice:
        # each file's header comments, through the end of that notice.
        local file
        for file in archive_read_support_filter_compress.c \
            archive_write_add_filter_compress.c; do
            echo "libarchive/$file:"
            awk '{ print } /The Regents of the University/ { regents = 1 } regents && /\*\// { exit }' \
                "libarchive/$file"
            echo
        done > LIBARCHIVE-BSD-NOTICES
    )
}
