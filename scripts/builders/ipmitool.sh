#!/usr/bin/env bash

build_ipmitool() {
    echo "==> building ipmitool"
    (
        cd "$WORK_DIR/ipmitool" || exit
        # The release is a Git tag archive without generated Autotools files.
        # configure.ac's version runs `git describe`; never let it find an
        # enclosing repository.
        GIT_CEILING_DIRECTORIES="$WORK_DIR" autoreconf --force --install >/dev/null
        # lanplus (IPMI 2.0 over the network) uses the pinned static OpenSSL.
        # The interactive shell would need readline. The IANA enterprise
        # number list is an unpinned runtime file and is not packaged;
        # --prefix=/usr makes ipmitool look for it where distributions put it.
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --build="$(cc -dumpmachine)" \
            --host="$AUTOCONF_HOST" \
            --prefix=/usr \
            --enable-intf-lanplus \
            --disable-ipmishell \
            --disable-intf-dbus \
            --disable-intf-usb \
            CPPFLAGS="-I$DEPS_PREFIX/include" \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS -L$DEPS_PREFIX/lib"
        grep -q '^#define IPMI_INTF_LANPLUS 1' config.h
        run_make -C lib
        run_make -C src/plugins
        run_make -C src ipmitool
        install_binary src/ipmitool ipmitool
    )
}
