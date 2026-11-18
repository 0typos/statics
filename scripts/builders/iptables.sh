#!/usr/bin/env bash

# The legacy (x_tables) firewall tools, for kernels and firmware without
# nf_tables; nft covers the rest. Every output carries upstream's -legacy
# suffix, so none of them can be taken for the nft-backed commands.

build_iptables() {
    echo "==> building iptables (legacy backend only)"
    (
        cd "$WORK_DIR/iptables" || exit
        # xtables-legacy-multi with every extension compiled in. No
        # nftables backend, libnfnetlink (nfnl_osf), or conntrack labels.
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --host="$AUTOCONF_HOST" \
            --enable-static \
            --disable-shared \
            --disable-nftables \
            --disable-libnfnetlink \
            --disable-connlabel \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make
        install_binary iptables/xtables-legacy-multi xtables-legacy-multi
        # It picks the command from argv[0].
        local family suffix
        for family in iptables ip6tables; do
            for suffix in '' -save -restore; do
                make_link xtables-legacy-multi "$family-legacy$suffix"
            done
        done
    )
}

build_ebtables() {
    echo "==> building ebtables (ebtables-legacy)"
    (
        cd "$WORK_DIR/ebtables" || exit
        # ebtables-legacy with libebtc and its extensions linked in. The
        # extensions register themselves from constructors that nothing
        # references, so the static libebtc is linked whole. The Perl save
        # script is not shipped. Ethernet protocol names come from
        # /etc/ethertypes when the target has one.
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --host="$AUTOCONF_HOST" \
            --prefix=/usr \
            --sysconfdir=/etc \
            --enable-static \
            --disable-shared \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make libebtc.la ebtables-standalone.o
        # shellcheck disable=SC2086  # a list of flags
        "$CC" $STATIC_LDFLAGS -o ebtables-legacy ebtables-standalone.o \
            -Wl,--whole-archive .libs/libebtc.a -Wl,--no-whole-archive
        install_binary ebtables-legacy ebtables-legacy
    )
}

build_arptables() {
    echo "==> building arptables (arptables-legacy)"
    (
        cd "$WORK_DIR/arptables" || exit
        # Zig's Linux headers leave out xt_MARK.h, which differs from
        # xt_mark.h only in case and just includes it.
        mkdir -p shim/linux/netfilter
        echo '#include <linux/netfilter/xt_mark.h>' > shim/linux/netfilter/xt_MARK.h
        # The Perl save and restore scripts are not shipped.
        run_make arptables-legacy CC="$CC" AR="$AR" \
            COPT_FLAGS="$STATIC_CFLAGS -I$PWD/shim" LDFLAGS="$STATIC_LDFLAGS"
        install_binary arptables-legacy arptables-legacy
    )
}
