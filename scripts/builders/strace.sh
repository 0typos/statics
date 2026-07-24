#!/usr/bin/env bash

build_strace() {
    echo "==> building strace"
    (
        cd "$WORK_DIR/strace" || exit
        CC="$CC" \
        CPPFLAGS="-I$REPO_ROOT/configs/strace-uapi -I$WORK_DIR/strace/bundled/linux/include/uapi" \
        ./configure \
            --host="$ZIG_TARGET" \
            --enable-bundled=yes \
            --enable-mpers=no \
            --enable-stacktrace=no \
            --with-libdw=no \
            --with-libiberty=no \
            --with-libselinux=no \
            --with-libunwind=no \
            CFLAGS="$STATIC_CFLAGS -Wno-macro-redefined \
                -include $WORK_DIR/strace/bundled/linux/include/uapi/linux/io_uring.h \
                -include $WORK_DIR/strace/bundled/linux/include/uapi/linux/io_uring/query.h \
                -include $WORK_DIR/strace/bundled/linux/include/uapi/linux/netdev.h \
                -include $WORK_DIR/strace/bundled/linux/include/uapi/linux/nl80211.h \
                -include $WORK_DIR/strace/bundled/linux/include/uapi/linux/rseq.h \
                -include $WORK_DIR/strace/bundled/linux/include/uapi/linux/v4l2-controls.h \
                -include $WORK_DIR/strace/bundled/linux/include/uapi/linux/videodev2.h \
                -include $REPO_ROOT/configs/strace-zig-uapi.h" \
            LDFLAGS="$STATIC_LDFLAGS"
        make -s -j"$JOBS"
        install_binary src/strace strace
    )
}
