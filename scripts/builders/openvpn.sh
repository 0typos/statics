#!/usr/bin/env bash

build_openvpn() {
    echo "==> building OpenVPN"
    (
        cd "$WORK_DIR/openvpn" || exit
        # Client and server with the pinned static OpenSSL and libcap-ng
        # (which upstream requires on Linux), configuring interfaces and
        # routes over netlink itself. Compression is the stub only: it
        # interoperates with peers that negotiate "compress" or "comp-lzo
        # no" but neither sends nor accepts compressed packets, so no LZO or
        # LZ4 library. No data channel offload (libnl and the ovpn kernel
        # module), plugins, PKCS#11, systemd, or SELinux, and no default
        # --dns-updown script, which the bundle does not ship.
        CC="$CC" AR="$AR" RANLIB="$RANLIB" \
        PKG_CONFIG_LIBDIR="$DEPS_PREFIX/lib/pkgconfig" \
        ./configure \
            --host="$AUTOCONF_HOST" \
            --prefix=/usr \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --disable-shared \
            --enable-static \
            --with-crypto-library=openssl \
            --disable-lzo \
            --disable-lz4 \
            --enable-comp-stub \
            --disable-dco \
            --disable-plugins \
            --disable-plugin-auth-pam \
            --disable-plugin-down-root \
            --disable-pkcs11 \
            --disable-selinux \
            --disable-systemd \
            --disable-dns-updown-by-default \
            --disable-unit-tests \
            OPENSSL_CFLAGS="-I$DEPS_PREFIX/include" \
            OPENSSL_LIBS="-L$DEPS_PREFIX/lib -lssl -lcrypto" \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make
        install_component_binary openvpn src/openvpn/openvpn openvpn
        # COPYING carries the OpenSSL and Apache-2.0 linking exceptions;
        # base64.c is BSD-3-Clause, with its notice in its header.
        awk '/^#/ { exit } { print }' src/openvpn/base64.c > OPENVPN-NOTICES
        grep -q 'Redistribution and use' OPENVPN-NOTICES || {
            echo "OPENVPN-NOTICES lacks base64.c's notice" >&2
            exit 1
        }
    )
}
