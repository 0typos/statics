#!/usr/bin/env bash

build_dropbear() {
    echo "==> building Dropbear"
    (
        cd "$WORK_DIR/dropbear" || exit
        # Zig's MIPS libc linker cannot optimize Autoconf's deliberately
        # prototype-less crypt/getpass probes. These functions are part of
        # the pinned musl sysroot, so provide the usual cross-build cache.
        ac_cv_func_crypt=yes \
        ac_cv_func_getpass=yes \
        ac_cv_func_getspnam=yes \
        CC="$CC" ./configure \
            --host="$ZIG_TARGET" \
            --disable-zlib \
            CFLAGS='-O0 -ffunction-sections -fdata-sections -Wno-undef' \
            LDFLAGS='-static -Wl,--gc-sections -Wl,-s'
        sed -i '/^CFLAGS/ s/-O0/-Os/' Makefile
        grep -q '^CFLAGS.*-Os' Makefile
        if [[ $ZIG_TARGET == mips* ]]; then
            sed -i \
                -e '/^CFLAGS/ s/ -fPIE//g' \
                -e '/^LDFLAGS/ s/ -pie//g' \
                Makefile
        fi
        make -s -j"$JOBS" \
            PROGRAMS='dropbear dbclient dropbearkey dropbearconvert scp' \
            MULTI=1 STATIC=1
        install_binary dropbearmulti dropbearmulti
    )

    local program
    for program in dropbear dbclient dropbearkey dropbearconvert scp; do
        make_link dropbearmulti "$program"
    done
}
