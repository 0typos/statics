#!/usr/bin/env bash

build_libtirpc() {
    echo "==> building libtirpc (static, for mount.nfs and showmount)"
    (
        cd "$WORK_DIR/libtirpc" || exit
        # RPC clients without /etc/netconfig or /etc/services (the patch).
        patch -s -p1 < "$REPO_ROOT/patches/libtirpc-without-etc-files.patch"
        # No GSSAPI (Kerberos), AUTH_DES, or symbol versioning; its own
        # /etc/rpc lookups (getrpcbynumber), which musl lacks and
        # nfs-utils' configure requires. musl has no <sys/queue.h>:
        # libevent's compat copy (BSD) supplies the TAILQ macros, and its
        # notice goes with libtirpc's. It installs into its own tree, apart
        # from DEPS_PREFIX, so no other builder finds it by accident.
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --host="$AUTOCONF_HOST" \
            --prefix="$WORK_DIR/libtirpc/install" \
            --sysconfdir=/etc \
            --disable-shared \
            --enable-static \
            --disable-gssapi \
            --disable-symvers \
            --enable-rpcdb \
            CPPFLAGS="-I$WORK_DIR/libevent/compat" \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make
        make -s install
        sed -n '1,/\*\//p' "$WORK_DIR/libevent/compat/sys/queue.h" > LIBTIRPC-NOTICES
    )
}

build_nfs_utils() {
    echo "==> building nfs-utils (mount.nfs and showmount)"
    (
        cd "$WORK_DIR/nfs-utils" || exit
        local tirpc=$WORK_DIR/libtirpc/install
        # The NFS client helpers only, with libtirpc: no NFSv4 server or
        # ID-mapping daemons, GSS/Kerberos, junctions (libxml2), nfsdctl
        # (readline), capabilities, or TCP wrappers. configure still
        # demands libevent, sqlite3, and libnl for daemons that are not
        # built here, so their checks are answered; the export cache code
        # that mount.nfs's support library compiles uses the real libnl
        # and libuuid headers (from DEPS_PREFIX and util-linux) but links
        # none of it. <sys/queue.h> comes from libevent, as for libtirpc.
        mkdir -p uuid-include/uuid
        cp "$WORK_DIR/util-linux/libuuid/src/uuid.h" uuid-include/uuid/
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --build="$(cc -dumpmachine)" \
            --host="$AUTOCONF_HOST" \
            --prefix=/usr \
            --sysconfdir=/etc \
            --disable-shared \
            --disable-nfsv4 \
            --disable-gss \
            --disable-junction \
            --disable-nfsdctl \
            --disable-nfsdcld \
            --disable-nfsrahead \
            --disable-nfs-fh-verify \
            --disable-caps \
            --disable-ldap \
            --disable-uuid \
            --without-tcp-wrappers \
            --without-systemd \
            --with-rpcgen=internal \
            ac_cv_lib_event_core_event_base_dispatch=yes \
            ac_cv_header_event2_event_h=yes \
            libsqlite3_cv_is_recent=unknown \
            PKG_CONFIG_LIBDIR="$tirpc/lib/pkgconfig:$DEPS_PREFIX/lib/pkgconfig" \
            CPPFLAGS="-I$DEPS_PREFIX/include/libnl3 -I$PWD/uuid-include -I$WORK_DIR/libevent/compat" \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS -L$tirpc/lib -L$WORK_DIR/util-linux/.libs"
        # rpcgen turns the MOUNT protocol's .x file into C during the
        # build, so it is compiled for the build host.
        run_make -C tools/rpcgen CC=cc CFLAGS=-O1 LDFLAGS=
        local dir
        for dir in include misc nfs export; do
            run_make -C "support/$dir"
        done
        # Not the fsidd daemon beside it.
        run_make -C support/reexport libreexport.a
        run_make -C utils/mount
        run_make -C utils/showmount
        # The BSD-licensed files among the support code, and libevent's
        # queue.h, carry their notices in their opening comments.
        local file
        {
            for file in support/nfs/atomicio.c support/nfs/conffile.c \
                support/nfs/fh_key_file.c support/nfs/mydaemon.c \
                support/nfs/strlcat.c support/nfs/strlcpy.c \
                support/misc/from_local.c; do
                echo "$file:"
                awk '/^#/ { exit } { print }' "$file"
            done
            echo "support/export/mount.x:"
            sed -n '1,/\*\//p' support/export/mount.x
            echo "libevent compat/sys/queue.h:"
            sed -n '1,/\*\//p' "$WORK_DIR/libevent/compat/sys/queue.h"
        } > NFS-UTILS-NOTICES
        install_binary utils/mount/mount.nfs mount.nfs
        install_binary utils/showmount/showmount showmount
        # mount.nfs picks its mode from its name.
        make_link mount.nfs mount.nfs4
        make_link mount.nfs umount.nfs
        make_link mount.nfs umount.nfs4
    )
}
