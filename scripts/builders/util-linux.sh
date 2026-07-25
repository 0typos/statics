#!/usr/bin/env bash

build_util_linux() {
    echo "==> building util-linux namespace tools"
    (
        cd "$WORK_DIR/util-linux" || exit
        PKG_CONFIG_PATH="$DEPS_PREFIX/lib/pkgconfig" \
        PKG_CONFIG_LIBDIR="$DEPS_PREFIX/lib/pkgconfig" \
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --build="$(cc -dumpmachine)" \
            --host="$AUTOCONF_HOST" \
            --prefix=/usr \
            --enable-lsns \
            --enable-nsenter \
            --enable-setpriv \
            --enable-unshare \
            --enable-libblkid \
            --enable-libmount \
            --enable-libsmartcols \
            --disable-shared \
            --enable-static \
            --disable-nls \
            --disable-libmount-udev-support \
            --with-cap-ng \
            --without-cryptsetup \
            --without-libmagic \
            --without-ncursesw \
            --without-python \
            --without-readline \
            --without-selinux \
            --without-systemd \
            --without-udev \
            CPPFLAGS="-I$DEPS_PREFIX/include" \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS -L$DEPS_PREFIX/lib"

        # setpriv's configure gate expects libcap-ng. The isolated include,
        # library, and pkg-config paths expose only the pinned static build.
        grep -q '^#define HAVE_LIBCAP_NG 1' config.h

        make -s -j"$JOBS" nsenter unshare lsns setpriv findmnt
        install_binary nsenter nsenter
        install_binary unshare unshare
        install_binary lsns lsns
        install_binary setpriv setpriv
        install_binary findmnt findmnt
    )
}
