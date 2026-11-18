#!/usr/bin/env bash

build_iputils() {
    echo "==> building iputils (ping, arping, tracepath)"
    (
        cd "$WORK_DIR/iputils" || exit
        meson_cross_file cross.ini
        # No libcap, libidn2, or gettext. ping tries an unprivileged ICMP
        # datagram socket first (net.ipv4.ping_group_range) and falls back to
        # a raw socket; without libcap it cannot drop capabilities it was
        # given, so it is meant to run as root or unprivileged, not setuid.
        # No clockdiff, man pages, or tests.
        # vcs_tag would take the version from any enclosing git checkout.
        export GIT_CEILING_DIRECTORIES=$WORK_DIR
        meson setup build \
            --cross-file cross.ini \
            --buildtype=plain \
            -Db_pie=false \
            -Dc_args="$STATIC_CFLAGS" \
            -Dc_link_args="$STATIC_LDFLAGS" \
            -DUSE_CAP=false \
            -DUSE_IDN=false \
            -DUSE_GETTEXT=false \
            -DBUILD_CLOCKDIFF=false \
            -DBUILD_MANS=false \
            -DNO_SETCAP_OR_SUID=true \
            -DSKIP_TESTS=true
        meson compile -C build -j "$JOBS" ping/ping arping tracepath
        install_binary build/ping/ping ping
        install_binary build/arping arping
        install_binary build/tracepath tracepath
        # ping takes IPv6 when called as ping6.
        make_link ping ping6
        # Documentation/LICENSE.BSD3 is the bare clause text; ping's
        # copyright line is in its header comment.
        awk '{ print } /Redistribution and use/ { r = 1 } r && /\*\// { exit }' \
            ping/ping.c > IPUTILS-NOTICES
        grep -q 'Regents of the University of California' IPUTILS-NOTICES || {
            echo "IPUTILS-NOTICES lacks ping's copyright" >&2
            exit 1
        }
    )
}
