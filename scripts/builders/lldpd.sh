#!/usr/bin/env bash

build_lldpd() {
    echo "==> building lldpd (lldpd and lldpcli)"
    (
        cd "$WORK_DIR/lldpd" || exit
        # The daemon and its client, with lldpd's bundled libevent and its
        # own JSON and key-value output. No SNMP agent, XML (libxml2),
        # json-c, readline (lldpcli reads commands without line editing),
        # seccomp, or privilege separation: that needs an _lldpd user and a
        # chroot directory that a target will not have, so the daemon keeps
        # running as root. Paths are the usual system ones. musl has no
        # sys/queue.h; the bundled libevent's BSD copy serves.
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --host="$AUTOCONF_HOST" \
            --prefix=/usr \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --runstatedir=/run \
            --disable-shared \
            --enable-static \
            --disable-hardening \
            --disable-privsep \
            --with-embedded-libevent \
            --without-snmp \
            --without-xml \
            --without-readline \
            --without-seccomp \
            --without-libbsd \
            CPPFLAGS="-I$PWD/libevent/compat" \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make
        install_binary src/daemon/lldpd lldpd
        install_binary src/client/lldpcli lldpcli
        # LICENSE is ISC and libevent/LICENSE BSD-3-Clause; lldpcli's UTF-8
        # code carries an MIT notice in its header comment.
        awk '{ print } /Copyright/ { c = 1 } c && /\*\// { exit }' \
            src/client/utf8.c > LLDPD-NOTICES
        grep -q 'Permission is hereby granted' LLDPD-NOTICES || {
            echo "LLDPD-NOTICES lacks the MIT notice of utf8.c" >&2
            exit 1
        }
    )
}
