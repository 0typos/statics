#!/usr/bin/env bash

build_dnsmasq() {
    echo "==> building dnsmasq"
    (
        cd "$WORK_DIR/dnsmasq" || exit
        # Upstream's default feature set, which needs nothing beyond libc:
        # DNS, DHCPv4 and DHCPv6 with router advertisements, TFTP, lease
        # scripts, authoritative zones, kernel ipsets, loop detection, and
        # packet dumps. No DNSSEC (nettle and GMP), IDN (libidn2), D-Bus,
        # ubus, conntrack marking, nftables sets, or Lua.
        run_make CC="$CC" \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        install_binary src/dnsmasq dnsmasq
    )
}
