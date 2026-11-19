#!/usr/bin/env bash

build_par2cmdline() {
    echo "==> building par2cmdline"
    (
        cd "$WORK_DIR/par2cmdline" || exit
        # No OpenMP: Zig ships no libgomp, and par2 then runs on one thread.
        CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" ./configure \
            --build="$(cc -dumpmachine)" \
            --host="$AUTOCONF_HOST" \
            --prefix=/usr \
            --disable-openmp \
            CXXFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make par2
        install_component_binary par2cmdline par2 par2
        # par2 picks its mode from its name, as upstream's links do.
        local directory name
        directory=$(archive_dir par2cmdline)
        for name in par2create par2verify par2repair; do
            ln -s par2 "$directory/$name"
        done
    )
}
