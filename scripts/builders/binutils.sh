#!/usr/bin/env bash

build_binutils() {
    echo "==> building binutils"
    (
        cd "$WORK_DIR/binutils" || exit
        # Native tools for this target alone: the BFD linker, the assembler,
        # and the object-file tools. No gold, gprof, gprofng, or libctf, and
        # no linker plugins (a static program cannot dlopen). Compressed
        # debug sections use the kit's zlib and libzstd. Each subdirectory
        # is configured during make and asks pkg-config for libzstd, so the
        # search path is exported and holds nothing but the kit's
        # libraries. --with-sysroot=/ is what lets ld take --sysroot at run
        # time.
        # The 2.47 tarball was cut with bfd/development.sh still in
        # development mode, which appends a date to every --version and
        # turns on the maintainers' internal checking; 2.46.1 and earlier
        # releases ship with both switches off.
        sed -i -E 's/^(development|experimental)=true$/\1=false/' bfd/development.sh
        if grep -Eq '^(development|experimental)=true$' bfd/development.sh; then
            echo "binutils: bfd/development.sh is still in development mode" >&2
            exit 1
        fi
        mkdir build
        cd build || exit
        export PKG_CONFIG_LIBDIR="$COMPRESSION_PREFIX/lib/pkgconfig"
        CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" ../configure \
            --build="$(cc -dumpmachine)" \
            --host="$AUTOCONF_HOST" \
            --target="$AUTOCONF_HOST" \
            --prefix=/usr \
            --with-sysroot=/ \
            --disable-shared \
            --disable-plugins \
            --disable-gold \
            --disable-gprof \
            --disable-gprofng \
            --disable-libctf \
            --disable-nls \
            --disable-werror \
            --enable-deterministic-archives \
            --with-system-zlib \
            --with-zstd \
            --without-debuginfod \
            --without-msgpack \
            --without-xxhash \
            CPPFLAGS="-I$COMPRESSION_PREFIX/include" \
            CFLAGS="$STATIC_CFLAGS" \
            CXXFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS -L$COMPRESSION_PREFIX/lib"
        run_make
        local tool
        for tool in ar objcopy objdump readelf strings; do
            install_component_binary binutils "binutils/$tool" "$tool"
        done
        install_component_binary binutils binutils/nm-new nm
        install_component_binary binutils binutils/strip-new strip
        install_component_binary binutils gas/as-new as
        install_component_binary binutils ld/ld-new ld
        cd .. || exit
        # libiberty's BSD-licensed sources carry their notice in the file.
        sed -s -n '1,/\*\//p' libiberty/bsearch_r.c libiberty/xatexit.c \
            > LIBIBERTY-BSD-NOTICES
    )
}
