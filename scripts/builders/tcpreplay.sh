#!/usr/bin/env bash

build_tcpreplay() {
    echo "==> building tcpreplay (tcpreplay, tcpprep, tcprewrite)"
    (
        cd "$WORK_DIR/tcpreplay" || exit
        # libpcap and the bundled libopts; packets go out through a
        # PF_PACKET socket. No libdnet, netmap, libxdp, or io_uring, and no
        # tcpdump decoding of packets (-v). tcpreplay-edit, tcpbridge,
        # tcpliveplay, and tcpcapinfo are not shipped.
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --host="$AUTOCONF_HOST" \
            --disable-nls \
            --disable-shared \
            --enable-static-link \
            --enable-local-libopts \
            --enable-force-pf \
            --disable-tuntap \
            --enable-year2038 \
            --with-libpcap="$DEPS_PREFIX" \
            CPPFLAGS="-I$DEPS_PREFIX/include" \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS -L$DEPS_PREFIX/lib"
        run_make
        local program
        for program in tcpreplay tcpprep tcprewrite; do
            install_binary "src/$program" "$program"
        done
        # LICENSE is the GPLv3 and libopts has its own COPYING files; two
        # tcpedit plugins linked into tcprewrite carry a BSD-3-Clause
        # notice in their header comments.
        local file
        for file in src/tcpedit/plugins/dlt_pppserial/pppserial.c \
            src/tcpedit/plugins/dlt_jnpr_ether/jnpr_ether.c; do
            echo "$file:"
            awk '{ print } /Copyright/ { c = 1 } c && /\*\// { exit }' "$file"
            echo
        done > TCPREPLAY-NOTICES
        grep -q 'Redistribution and use' TCPREPLAY-NOTICES || {
            echo "TCPREPLAY-NOTICES lacks the BSD notices" >&2
            exit 1
        }
    )
}
