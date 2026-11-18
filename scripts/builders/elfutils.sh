#!/usr/bin/env bash

build_libelf() {
    echo "==> building elfutils (libelf only)"
    (
        cd "$WORK_DIR/elfutils" || exit
        # Only libelf, for bpftool, which links it from this tree: no libdw,
        # libasm, tools, or debuginfod, and so no argp, fts, or obstack,
        # which musl lacks and configure insists on for those parts. zlib
        # is required; no bzip2, xz, or zstd ELF section compression. The
        # __thread probe links a shared object, which fails with -static.
        ac_cv_search_argp_parse='none required' \
        ac_cv_search_fts_close='none required' \
        ac_cv_search__obstack_free='none required' \
        ac_cv_tls=yes \
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --host="$AUTOCONF_HOST" \
            --disable-nls \
            --disable-debuginfod \
            --disable-libdebuginfod \
            --disable-demangler \
            --disable-symbol-versioning \
            --disable-textrelcheck \
            --with-zlib \
            --without-bzlib \
            --without-lzma \
            --without-zstd \
            CPPFLAGS="-I$COMPRESSION_PREFIX/include" \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS -L$COMPRESSION_PREFIX/lib"
        # libelf.a absorbs every object of libeu, the tools' helper library,
        # but uses only its eu_tsearch. The rest would clash with zlib's
        # crc32, and color and printversion need argp.h.
        run_make -C lib libeu.a libeu_a_OBJECTS=eu-search.o
        run_make -C libelf libelf.a
        # libelf's elf.h comes from glibc, under the LGPL-2.1-or-later.
        awk '{ print } /Copyright/ { c = 1 } c && /\*\// { exit }' \
            libelf/elf.h > ELFUTILS-ELF-H-NOTICE
    )
}
