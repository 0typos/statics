#!/usr/bin/env bash

build_tcpreplay() {
    echo "==> building tcpreplay (tcpreplay, tcpprep, tcprewrite)"
    (
        cd "$WORK_DIR/tcpreplay" || exit
        # libpcap and the bundled libopts; packets go out through a
        # PF_PACKET socket. No libdnet, netmap, libxdp, or io_uring, and no
        # tcpdump decoding of packets (-v). tcpreplay-edit, tcpbridge,
        # tcpliveplay, and tcpcapinfo are not shipped. Its probes for the
        # libraries a newer libpcap may need (libnl, D-Bus) are answered no:
        # this libpcap needs neither, and libnl can appear in DEPS_PREFIX
        # while this runs, when build_libnl installs it.
        ac_cv_lib_nl_nl_cache_alloc=no \
        ac_cv_lib_nl_genl_3_genl_connect=no \
        ac_cv_lib_nl_3_nl_cache_alloc=no \
        ac_cv_lib_dbus_1_dbus_malloc=no \
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
            --without-tcpdump \
            CPPFLAGS="-I$DEPS_PREFIX/include" \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS -L$DEPS_PREFIX/lib"
        run_make
        local program
        for program in tcpreplay tcpprep tcprewrite; do
            install_binary "src/$program" "$program"
        done
        # LICENSE is the GPLv3 and libopts has its own COPYING files. These
        # linked files carry BSD notices in their header comments (2-, 3-,
        # and 4-clause): print each header through its license text.
        local file
        for file in src/common/err.c src/common/dlt_names.c lib/tree.h lib/queue.h \
            src/tcpedit/plugins/dlt_pppserial/pppserial.c \
            src/tcpedit/plugins/dlt_pppserial/pppserial_api.c \
            src/tcpedit/plugins/dlt_jnpr_ether/jnpr_ether.c \
            src/tcpedit/plugins/dlt_jnpr_ether/jnpr_ether_api.c; do
            echo "$file:"
            awk '{ print } /Redistribution and use/ { r = 1 } r && /\*\// { exit }' "$file"
            echo
        done > TCPREPLAY-NOTICES
        if [[ $(grep -c 'Redistribution and use' TCPREPLAY-NOTICES) -ne 8 ]] ||
            ! grep -q 'advertising materials' TCPREPLAY-NOTICES; then
            echo "TCPREPLAY-NOTICES lacks a BSD notice" >&2
            exit 1
        fi
    )
}
