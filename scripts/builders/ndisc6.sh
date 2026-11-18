#!/usr/bin/env bash

build_ndisc6() {
    echo "==> building ndisc6 (ndisc6, rdisc6, rltraceroute6, tcptraceroute6)"
    (
        cd "$WORK_DIR/ndisc6" || exit
        # No NLS. The rdnssd daemon and the tcpspray, name2addr, and Perl
        # helper programs are not built.
        CC="$CC" ./configure \
            --host="$AUTOCONF_HOST" \
            --disable-nls \
            --disable-suid-install \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make ndisc6 rdisc6 rltraceroute6 tcptraceroute6
        local program
        for program in ndisc6 rdisc6 rltraceroute6 tcptraceroute6; do
            install_binary "$program" "$program"
        done
    )
}
