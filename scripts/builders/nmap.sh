#!/usr/bin/env bash

build_nmap() {
    echo "==> building Nmap and Ncat"
    (
        cd "$WORK_DIR/nmap" || exit
        patch -s -p1 < "$REPO_ROOT/patches/nmap-libdnet-clang.patch"
        CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" \
            PKG_CONFIG=false \
            CONFIG_SITE="$REPO_ROOT/configs/nmap-config.site" \
            ./configure \
            --build="$(cc -dumpmachine)" \
            --host="$AUTOCONF_HOST" \
            --prefix=/usr \
            --disable-nls \
            --without-ndiff \
            --without-zenmap \
            --without-nping \
            --without-liblua \
            --without-libssh2 \
            --with-openssl="$DEPS_PREFIX" \
            --with-libpcap="$DEPS_PREFIX" \
            --with-libpcre=included \
            --with-libz=included \
            --with-libdnet=included \
            --with-liblinear=included \
            CPPFLAGS="-I$DEPS_PREFIX/include" \
            CFLAGS="$STATIC_CFLAGS" \
            CXXFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS -L$DEPS_PREFIX/lib"

        # Zig 0.16's -MM mode can select host headers when Nmap asks it to
        # scan many source files at once. These files are optional and have
        # no prerequisites of their own, so pre-create them for this clean,
        # one-shot build instead of emitting misleading diagnostics.
        touch \
            makefile.dep \
            libnetutil/makefile.dep \
            ncat/makefile.dep \
            nsock/src/makefile.dep
        make -s -j"$JOBS" nmap build-ncat
        install_binary nmap nmap
        install_binary ncat/ncat ncat

        local data_file
        for data_file in \
            nmap-mac-prefixes \
            nmap-os-db \
            nmap-protocols \
            nmap-rpc \
            nmap-service-probes \
            nmap-services \
            docs/nmap.dtd \
            docs/nmap.xsl; do
            install_output_file \
                "$data_file" \
                "share/nmap/${data_file##*/}"
        done
    )
}
