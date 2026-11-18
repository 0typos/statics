#!/usr/bin/env bash

build_stunnel() {
    echo "==> building stunnel"
    (
        cd "$WORK_DIR/stunnel" || exit
        # The pinned static OpenSSL. One process per connection (fork
        # mode) on every target: the 32-bit OpenSSL is built without
        # threads, which stunnel's pthread mode refuses, and musl has no
        # ucontext. No TCP wrappers, systemd socket activation, FIPS, or
        # the libstunnel LD_PRELOAD helper.
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --host="$AUTOCONF_HOST" \
            --prefix=/usr \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --disable-shared \
            --disable-libwrap \
            --disable-systemd \
            --disable-fips \
            --with-threads=fork \
            --with-ssl="$DEPS_PREFIX" \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make -C src stunnel
        install_component_binary stunnel src/stunnel stunnel
    )
}
