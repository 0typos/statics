#!/usr/bin/env bash

build_openssl() {
    echo "==> building OpenSSL"
    (
        cd "$WORK_DIR/openssl" || exit
        local extra_options=()
        if [[ -n $OPENSSL_THREAD_OPTION ]]; then
            extra_options+=("$OPENSSL_THREAD_OPTION")
        fi
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./Configure \
            "linux-generic$TARGET_BITS" \
            no-asm \
            no-docs \
            no-module \
            no-shared \
            no-tests \
            "${extra_options[@]}" \
            --prefix="$DEPS_PREFIX" \
            --openssldir=/etc/ssl \
            "$STATIC_CFLAGS" \
            "$STATIC_LDFLAGS"
        make -s -j"$JOBS"
        make -s install_dev
        install_binary apps/openssl openssl
    )
}

build_libpcap() {
    echo "==> building libpcap"
    (
        cd "$WORK_DIR/libpcap" || exit
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --host="$ZIG_TARGET" \
            --prefix="$DEPS_PREFIX" \
            --disable-shared \
            --disable-bluetooth \
            --disable-dbus \
            --disable-netmap \
            --disable-rdma \
            --disable-usb \
            --without-dag \
            --without-dpdk \
            --without-libnl \
            --without-septel \
            --without-snf \
            --without-turbocap \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        make -s -j"$JOBS"
        make -s install
    )
}

build_libmnl() {
    echo "==> building libmnl"
    (
        cd "$WORK_DIR/libmnl" || exit
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --host="$ZIG_TARGET" \
            --prefix="$DEPS_PREFIX" \
            --disable-shared \
            --enable-static \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        make -s -j"$JOBS"
        make -s install
    )
}

build_dependencies() {
    build_openssl
    build_libpcap
    build_libmnl
}
