#!/usr/bin/env bash

build_strace() {
    echo "==> building strace"
    (
        cd "$WORK_DIR/strace" || exit
        # strace's --enable-bundled adds its newer UAPI headers with -isystem,
        # which Zig 0.17 searches after its own older libc headers. Pass them
        # with -I instead, which wins over every system directory.
        local uapi=$WORK_DIR/strace/bundled/linux karch
        # configure.ac's arch-to-karch mapping, for this repo's targets.
        case $AUTOCONF_HOST in
            x86_64-* | i686-*) karch=x86 ;;
            aarch64-*) karch=arm64 ;;
            arm-*) karch=arm ;;
            mips*) karch=mips ;;
            powerpc*) karch=powerpc ;;
            riscv64-*) karch=riscv ;;
            s390x-*) karch=s390 ;;
            *) echo "strace: no karch for $AUTOCONF_HOST" >&2; exit 1 ;;
        esac
        local cppflags="-I$uapi/include/uapi"
        if [[ -d $uapi/arch/$karch ]]; then
            cppflags="-I$uapi/arch/$karch/include/uapi $cppflags"
        fi
        CC="$CC" \
        CPPFLAGS="$cppflags" \
        ./configure \
            --host="$AUTOCONF_HOST" \
            --enable-bundled=no \
            --enable-mpers=no \
            --enable-stacktrace=no \
            --with-libdw=no \
            --with-libiberty=no \
            --with-libselinux=no \
            --with-libunwind=no \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make
        install_binary src/strace strace
    )
}
