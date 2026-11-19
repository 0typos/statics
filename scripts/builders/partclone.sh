#!/usr/bin/env bash

build_partclone() {
    echo "==> building partclone"
    (
        cd "$WORK_DIR/partclone" || exit
        local e2fs=$WORK_DIR/e2fsprogs xxh=$WORK_DIR/xxhash
        # Checksums through aligned copies, for strict-alignment targets.
        patch -s -p1 < "$REPO_ROOT/patches/partclone-alignment.patch"
        # A tag archive: generate the build system, without gettext, whose
        # autoconf macros the builder lacks (and NLS is off everywhere).
        sed -i -e '/^AM_GNU_GETTEXT/d' -e '\|po/Makefile.in|d' configure.ac
        sed -i 's/^SUBDIRS=.*/SUBDIRS= src/' Makefile.am
        mkdir -p m4
        autoreconf -fi >/dev/null 2>&1
        # ext2/3/4, FAT, and raw (dd) images, plus the generic restore,
        # image check, and info tools, with e2fsprogs' libext2fs,
        # libcom_err, and libuuid and libxxhash from their build trees.
        # Not btrfs (its bundled btrfs-progs code alone is 280 KB of xz),
        # XFS (liburcu), or NTFS (ntfs-3g). ac_cv_func_EVP_MD_CTX_reset=no
        # makes torrent_helper.c hash with OpenSSL's SHA1_Init, which links
        # only SHA-1, not the EVP and provider layers (about 1.5 MB more in
        # every binary).
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --build="$(cc -dumpmachine)" \
            --host="$AUTOCONF_HOST" \
            --prefix=/usr \
            --disable-shared \
            --enable-static-linking \
            --enable-extfs \
            --enable-fat \
            ac_cv_func_EVP_MD_CTX_reset=no \
            ac_cv_lib_jitterentropy_jent_entropy_collector_alloc=no \
            UUID_CFLAGS="-I$e2fs/lib" UUID_LIBS="-L$e2fs/lib -luuid" \
            XXHASH_CFLAGS="-I$xxh" XXHASH_LIBS="-L$xxh -lxxhash" \
            EXT2FS_CFLAGS="-I$e2fs/lib" EXT2FS_LIBS="-L$e2fs/lib -lext2fs" \
            OPENSSL_CFLAGS="-I$DEPS_PREFIX/include" OPENSSL_LIBS="-L$DEPS_PREFIX/lib -lcrypto" \
            ZLIB_CFLAGS=" " ZLIB_LIBS=" " ZSTD_CFLAGS=" " ZSTD_LIBS=" " \
            CPPFLAGS="-I$e2fs/lib -I$xxh -I$DEPS_PREFIX/include" \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS -L$e2fs/lib -L$DEPS_PREFIX/lib"
        run_make -C src
        local program
        for program in extfs fat dd restore chkimg info; do
            install_binary "src/partclone.$program" "partclone.$program"
        done
        for program in ext2 ext3 ext4; do
            make_link partclone.extfs "partclone.$program"
        done
        for program in vfat fat12 fat16 fat32; do
            make_link partclone.fat "partclone.$program"
        done
    )
}
