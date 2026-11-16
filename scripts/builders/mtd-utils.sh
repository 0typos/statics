#!/usr/bin/env bash

MTD_UTILS_PROGRAMS=(
    flash_erase flashcp nanddump nandwrite mtdinfo
    ubiattach ubidetach ubinfo ubimkvol ubirmvol ubiupdatevol
)

build_mtd_utils() {
    echo "==> building mtd-utils"
    (
        cd "$WORK_DIR/mtd-utils" || exit
        # MTD and UBI device tools only: no image builders (mkfs.ubifs,
        # mkfs.jffs2), so no zlib, LZO, zstd, xattr, SELinux, or crypto.
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --host="$AUTOCONF_HOST" \
            --without-tests \
            --without-lsmtd \
            --without-jffs \
            --without-ubifs \
            --without-zlib \
            --without-xattr \
            --without-lzo \
            --without-zstd \
            --without-selinux \
            --without-crypto \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make "${MTD_UTILS_PROGRAMS[@]}"
        local program
        for program in "${MTD_UTILS_PROGRAMS[@]}"; do
            install_binary "$program" "$program"
        done
        # flashcp is BSD-licensed and carries its notice in the file.
        sed -n '1,/\*\//p' misc-utils/flashcp.c > MTD-UTILS-BSD-NOTICES
    )
}
