#!/usr/bin/env bash

build_cifs_utils() {
    echo "==> building cifs-utils (mount.cifs only)"
    (
        cd "$WORK_DIR/cifs-utils" || exit
        # mount.cifs alone: no cifs.upcall or cifscreds (Kerberos and
        # keyutils), no cifs.idmap, get/setcifsacl, or smbinfo (winbind),
        # no PAM or systemd, and no talloc (the patch explains what that
        # leaves out). libcap-ng, already built, lets it drop the
        # capabilities it does not need. musl's malloc(0) and realloc(p, 0)
        # return usable pointers, which configure cannot test when cross.
        patch -s -p1 < "$REPO_ROOT/patches/cifs-utils-no-talloc.patch"
        autoreconf -fi >/dev/null 2>&1
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --build="$(cc -dumpmachine)" \
            --host="$AUTOCONF_HOST" \
            --prefix=/usr \
            --disable-cifsupcall \
            --disable-cifscreds \
            --disable-cifsidmap \
            --disable-cifsacl \
            --disable-smbinfo \
            --disable-pythontools \
            --disable-pam \
            --disable-systemd \
            --disable-man \
            --disable-pie \
            --with-libcap-ng=yes \
            ac_cv_func_malloc_0_nonnull=yes \
            ac_cv_func_realloc_0_nonnull=yes \
            CPPFLAGS="-I$DEPS_PREFIX/include" \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS -L$DEPS_PREFIX/lib"
        run_make mount.cifs
        install_binary mount.cifs mount.cifs
    )
}
