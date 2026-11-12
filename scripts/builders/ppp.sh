#!/usr/bin/env bash

build_ppp() {
    echo "==> building pppd"
    (
        cd "$WORK_DIR/ppp" || exit
        # No plugins (static), no OpenSSL, PAM, or libpcap: MS-CHAP and MPPE
        # use pppd's built-in crypto; EAP-TLS, PEAP, and active-filter are off.
        # The prefixes make pppd read /etc/ppp, as on any distribution.
        CC="$CC" ./configure \
            --host="$AUTOCONF_HOST" \
            --prefix=/usr \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --runstatedir=/run \
            --disable-shared \
            --enable-static \
            --disable-plugins \
            --disable-eaptls \
            --disable-peap \
            --disable-systemd \
            --without-openssl \
            --without-pam \
            --without-pcap \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make -C pppd pppd
        install_binary pppd/pppd pppd

        # pppd's files carry their own notices, some mid-file (OpenSSL's
        # Apache-2.0 DES code, RSA's MD4/MD5), which binary redistribution
        # must reproduce: collect every notice-bearing comment block from each
        # source file compiled into pppd and its crypto library.
        local object source
        for object in pppd/pppd-*.o pppd/libppp_crypto_la-*.o; do
            source=${object#pppd/pppd-}
            source=${source#pppd/libppp_crypto_la-}
            source=pppd/${source%.o}.c
            printf '==> %s\n' "$source"
            awk '
                /\/\*/ { block = ""; inside = 1 }
                inside { block = block $0 "\n" }
                inside && /\*\// {
                    inside = 0
                    if (block ~ /[Cc]opyright|\(C\)|[Ll]icen[cs]e|Permission|Redistribution|[Pp]ublic [Dd]omain/)
                        printf "%s\n", block
                }
            ' "$source"
        done > PPPD-NOTICES
        printf '%s\n' \
            'The Apache License 2.0 named above is reproduced in ../openssl/LICENSE.txt.' \
            >> PPPD-NOTICES
    )
}
