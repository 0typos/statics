#!/usr/bin/env bash

build_e2fsprogs() {
    echo "==> building e2fsprogs (e2fsck, dumpe2fs, tune2fs, mke2fs)"
    (
        cd "$WORK_DIR/e2fsprogs" || exit
        # Modern musl dropped the LFS64 aliases and llseek, and off_t is
        # always 64-bit: the legacy llseek fallbacks in lib/{blkid,ext2fs}
        # break 32-bit builds (_syscall5) and ppc64 (__u64 typedef clash via
        # <linux/unistd.h>). The patch routes both through plain lseek.
        patch -s -p1 < "$REPO_ROOT/patches/e2fsprogs-llseek-musl.patch"
        # BUILD_CC compiles the build-host helper generators; the bundled
        # libext2fs/libe2p/libuuid stay internal so the tools are self-contained.
        # __SANE_USERSPACE_TYPES__: ppc64's uapi asm/types.h keeps the legacy
        # int-l64 __u64 (unsigned long) for userspace unless this is defined,
        # which clashes with ext2_types.h's unsigned long long. The define is
        # the kernel-documented opt-in to int-ll64 and a no-op elsewhere.
        CC="$CC" AR="$AR" RANLIB="$RANLIB" BUILD_CC=cc ./configure \
            --host="$AUTOCONF_HOST" \
            --disable-nls \
            --disable-fuse2fs \
            --disable-uuidd \
            --disable-testio-debug \
            CFLAGS="$STATIC_CFLAGS -D__SANE_USERSPACE_TYPES__" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make
        install_binary e2fsck/e2fsck e2fsck
        install_binary misc/dumpe2fs dumpe2fs
        install_binary misc/tune2fs tune2fs
        install_binary misc/mke2fs mke2fs
        make_link e2fsck fsck.ext2
        make_link e2fsck fsck.ext3
        make_link e2fsck fsck.ext4
        make_link mke2fs mkfs.ext4
    )
}
