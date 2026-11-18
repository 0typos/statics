#!/usr/bin/env bash

build_busybox() {
    echo "==> building BusyBox"
    (
        cd "$WORK_DIR/busybox" || exit
        make defconfig >/dev/null
        "$REPO_ROOT/scripts/merge-kconfig.sh" .config "$REPO_ROOT/configs/busybox.fragment"
        KCONFIG_NOTIMESTAMP=1 make oldconfig </dev/null >/dev/null
        KCONFIG_NOTIMESTAMP=1 run_make \
            CC="$CC" HOSTCC=cc AR="$AR" RANLIB="$RANLIB" \
            KCFLAGS='-Wno-ignored-optimization-argument -Wno-unused-command-line-argument' \
            LDFLAGS='-Wl,-s' \
            SKIP_STRIP=y
        install_binary busybox busybox
    )

    # ping, ping6, arping, traceroute, and traceroute6 are the iputils and
    # traceroute programs instead; `busybox ping` still reaches the applet.
    local applet
    for applet in nc netcat nslookup wget telnet arp route ifconfig netstat; do
        make_link busybox "$applet"
    done
}
