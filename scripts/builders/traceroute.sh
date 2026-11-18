#!/usr/bin/env bash

build_traceroute() {
    echo "==> building traceroute"
    (
        cd "$WORK_DIR/traceroute" || exit
        # The modern traceroute (traceroute.sourceforge.net): UDP, ICMP
        # (-I), TCP SYN (-T), UDP to one port (-U), and the other modules,
        # all built in. Its libsupp is linked statically.
        run_make CC="$CC" AR="$AR" RANLIB="$RANLIB" \
            CFLAGS="$STATIC_CFLAGS" LDFLAGS="$STATIC_LDFLAGS"
        install_binary traceroute/traceroute traceroute
        # A name ending in 6 selects IPv6.
        make_link traceroute traceroute6
    )
}
