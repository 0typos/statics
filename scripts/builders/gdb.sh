#!/usr/bin/env bash

build_gdbserver() {
    echo "==> building gdbserver"
    (
        cd "$WORK_DIR/gdb" || exit
        # Only gdbserver and the libraries it links (gdbsupport, gnulib,
        # libiberty): no gdb, Python, expat, debuginfod, or in-process agent.
        mkdir build
        cd build || exit
        CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" ../configure \
            --build="$(cc -dumpmachine)" \
            --host="$AUTOCONF_HOST" \
            --disable-gdb \
            --enable-gdbserver \
            --disable-inprocess-agent \
            --disable-binutils \
            --disable-gas \
            --disable-gold \
            --disable-gprof \
            --disable-ld \
            --disable-libctf \
            --disable-libdecnumber \
            --disable-readline \
            --disable-sim \
            --disable-nls \
            --disable-werror \
            --without-python \
            --without-expat \
            --without-debuginfod \
            --without-zstd \
            --without-xxhash \
            CFLAGS="$STATIC_CFLAGS" \
            CXXFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make all-gdbserver
        install_binary gdbserver/gdbserver gdbserver
        cd .. || exit
        # libiberty's BSD-licensed sources carry their notice in the file.
        sed -s -n '1,/\*\//p' libiberty/bsearch_r.c libiberty/xatexit.c \
            > LIBIBERTY-BSD-NOTICES
    )
}
