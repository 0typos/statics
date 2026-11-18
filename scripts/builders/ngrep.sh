#!/usr/bin/env bash

build_ngrep() {
    echo "==> building ngrep"
    (
        cd "$WORK_DIR/ngrep" || exit
        # Its bundled GNU regex rather than PCRE2, IPv6 on, and no tcpkill.
        CC="$CC" ./configure \
            --host="$AUTOCONF_HOST" \
            --enable-ipv6 \
            --disable-tcpkill \
            --disable-container-resolution \
            --with-pcap-includes="$DEPS_PREFIX/include" \
            CPPFLAGS="-I$DEPS_PREFIX/include" \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS -L$DEPS_PREFIX/lib"
        # Its rule for the regex object passes $(MAKEFLAGS) as arguments,
        # which reads make's -s as a target; build that object directly.
        run_make -C regex-0.12 regex.o CFLAGS="$STATIC_CFLAGS"
        # The binary is already stripped at link time (-Wl,-s); the host's
        # strip cannot read foreign ELF.
        run_make STRIP=true
        install_binary ngrep ngrep
    )
}
