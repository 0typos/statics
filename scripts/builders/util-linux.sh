#!/usr/bin/env bash

build_util_linux() {
    echo "==> building util-linux"
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

        local programs=(
            nsenter unshare lsns setpriv findmnt
            lsblk blkid sfdisk losetup mount umount dmesg
        )
        run_make "${programs[@]}"
        local program
        for program in "${programs[@]}"; do
            install_binary "$program" "$program"
        done
        # libuuid (sfdisk) and libcommon's xxhash and crc64 (libblkid) are
        # BSD- and MIT-licensed and carry their notices in the file.
        sed -s -n '1,/\*\//p' libuuid/src/gen_uuid.c lib/xxhash.c lib/crc64.c \
            > UTIL-LINUX-NOTICES
    )
}
