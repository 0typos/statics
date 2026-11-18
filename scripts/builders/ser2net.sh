#!/usr/bin/env bash

# libyaml and gensio install into their own trees, apart from DEPS_PREFIX,
# so no other builder finds them by accident.

build_libyaml() {
    echo "==> building libyaml (static, for ser2net's configuration)"
    (
        cd "$WORK_DIR/libyaml" || exit
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --host="$AUTOCONF_HOST" \
            --prefix="$WORK_DIR/libyaml/install" \
            --disable-shared \
            --enable-static \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make -C src
        make -s -C src install
        make -s install-data
    )
}

build_gensio() {
    echo "==> building gensio (static, for ser2net)"
    (
        cd "$WORK_DIR/gensio" || exit
        # Only the gensios a serial console server needs: TCP and UDP,
        # Unix sockets, serial devices and ptys, telnet with RFC 2217,
        # stdio, files, and the small helpers ser2net's defaults name. No
        # TLS (OpenSSL) or certauth, SCTP, mDNS, sound, IPMI SOL, AX.25,
        # radio modems, or language bindings.
        local gensios=(
            --with-all-gensios=no
            --with-net=yes --with-dgram=yes --with-stdio=yes --with-pty=yes
            --with-serialdev=yes --with-telnet=yes --with-conacc=yes
            --with-dummy=yes --with-echo=yes --with-file=yes --with-trace=yes
            --with-keepopen=yes --with-msgdelim=yes --with-mux=yes
        )
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --host="$AUTOCONF_HOST" \
            --prefix="$WORK_DIR/gensio/install" \
            --disable-shared \
            --enable-static \
            --disable-doc \
            "${gensios[@]}" \
            --with-openssl=no \
            --with-sctp=no \
            --with-mdns=no \
            --with-avahi=no \
            --with-dnssd=no \
            --with-alsa=no \
            --with-portaudio=no \
            --with-udev=no \
            --with-openipmi=no \
            --with-glib=no \
            --with-tcl=no \
            --with-cplusplus=no \
            --with-swig=no \
            --with-python=no \
            --with-go=no \
            --with-tcp-wrappers=no \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make -C lib
        # Not lib install: its hook expects a dynamic-module directory.
        make -s -C lib install-libLTLIBRARIES
        make -s -C include install
    )
}

build_ser2net() {
    echo "==> building ser2net"
    (
        cd "$WORK_DIR/ser2net" || exit
        local gensio=$WORK_DIR/gensio/install libyaml=$WORK_DIR/libyaml/install
        # gensio and libyaml from the builders above. No PAM, so the
        # admin interface's authentication is gensio's own; no sysfs LEDs.
        # Static archives need their dependants first: configure's own
        # -lgensio checks then resolve against libgensioosh too.
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --host="$AUTOCONF_HOST" \
            --prefix=/usr \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --with-pam=no \
            CPPFLAGS="-I$gensio/include -I$libyaml/include" \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS -L$gensio/lib -L$libyaml/lib" \
            LIBS="-lgensiomdns -lgensio -lgensioosh"
        run_make ser2net
        install_binary ser2net ser2net
    )
}
