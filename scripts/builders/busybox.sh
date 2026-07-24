#!/usr/bin/env bash

build_busybox() {
    echo "==> building BusyBox"
    (
        cd "$WORK_DIR/busybox" || exit
        make defconfig >/dev/null
        "$REPO_ROOT/scripts/merge-kconfig.sh" .config "$REPO_ROOT/configs/busybox.fragment"
        KCONFIG_NOTIMESTAMP=1 make oldconfig </dev/null >/dev/null
        KCONFIG_NOTIMESTAMP=1 make -s -j"$JOBS" \
            CC="$CC" HOSTCC=cc AR="$AR" RANLIB="$RANLIB" \
            KCFLAGS='-Wno-ignored-optimization-argument -Wno-unused-command-line-argument' \
            LDFLAGS='-Wl,-s' \
            SKIP_STRIP=y
        install_binary busybox busybox
    )

    local applet
    for applet in nc netcat ping ping6 traceroute traceroute6 nslookup wget \
        telnet arp arping route ifconfig netstat; do
        make_link busybox "$applet"
    done
}
