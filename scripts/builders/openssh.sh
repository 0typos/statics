#!/usr/bin/env bash

build_sftp_server() {
    echo "==> building OpenSSH sftp-server"
    (
        cd "$WORK_DIR/openssh" || exit
        # Only sftp-server, which Dropbear runs for the SFTP subsystem. It
        # does no cryptography or compression, so OpenSSL and zlib are off.
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --build="$(cc -dumpmachine)" \
            --host="$AUTOCONF_HOST" \
            --without-openssl \
            --without-zlib \
            --disable-security-key \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS"
        run_make sftp-server
        install_binary sftp-server sftp-server
    )
}
