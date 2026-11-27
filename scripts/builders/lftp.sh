#!/usr/bin/env bash

build_readline() {
    echo "==> building readline (static, for lftp and sqlite3)"
    (
        cd "$WORK_DIR/readline" || exit
        local ncurses=$WORK_DIR/ncurses/install pic=
        # PIC on MIPS, as for bash: readline's sigsetjmp needs it there.
        case $STATICS_ARCH in
            mips | mipsel) pic=-fPIC ;;
        esac
        # lftp requires readline, and sqlite3 uses it. Terminal handling comes from the static
        # ncurses. --build makes every target a cross build; the answers
        # are what its run-time probes find on Linux with musl. It installs
        # into its own tree, apart from DEPS_PREFIX.
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --build="$(cc -dumpmachine)" \
            --host="$AUTOCONF_HOST" \
            --prefix="$WORK_DIR/readline/install" \
            --disable-shared \
            --enable-static \
            --disable-install-examples \
            --with-curses \
            bash_cv_func_sigsetjmp=present \
            bash_cv_must_reinstall_sighandlers=no \
            bash_cv_func_strcoll_broken=no \
            CPPFLAGS="-I$ncurses/include/ncurses -I$ncurses/include" \
            CFLAGS="$STATIC_CFLAGS $pic" \
            LDFLAGS="$STATIC_LDFLAGS -L$ncurses/lib"
        run_make static
        make -s install-static
    )
}

build_lftp() {
    echo "==> building lftp"
    (
        cd "$WORK_DIR/lftp" || exit
        local ncurses=$WORK_DIR/ncurses/install readline=$WORK_DIR/readline/install
        local expat=$WORK_DIR/expat/install pic=
        # As for bash: musl's MIPS dlsym, which lftp calls for its module
        # hooks, derives $gp from $t9, which a non-PIC jal leaves unset;
        # lftp crashed at its first mirror. PIC calls load $t9 first.
        case $STATICS_ARCH in
            mips | mipsel) pic=-fPIC ;;
        esac
        # OpenSSL for FTPS and HTTPS (not GnuTLS), zlib for MODE Z, expat
        # for WebDAV listings, and readline on the static ncurses. SFTP and
        # FISH run an external ssh client, such as the bundled dbclient.
        # No NLS, libidn2, SOCKS, or loadable protocol modules. -UNDEBUG
        # keeps its assertions, as upstream builds (Zig defines NDEBUG when
        # optimizing).
        CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" ./configure \
            --build="$(cc -dumpmachine)" \
            --host="$AUTOCONF_HOST" \
            --prefix=/usr \
            --sysconfdir=/etc \
            --disable-shared \
            --disable-nls \
            --without-gnutls \
            --with-openssl="$DEPS_PREFIX" \
            --with-zlib="$COMPRESSION_PREFIX" \
            --with-expat="$expat" \
            --with-readline="$readline" \
            --with-readline-lib="-lreadline -lncurses" \
            --without-libidn2 \
            CPPFLAGS="-I$DEPS_PREFIX/include -I$COMPRESSION_PREFIX/include -I$expat/include -I$readline/include -I$ncurses/include/ncurses -I$ncurses/include" \
            CFLAGS="$STATIC_CFLAGS -UNDEBUG $pic" \
            CXXFLAGS="$STATIC_CFLAGS -UNDEBUG $pic" \
            LDFLAGS="$STATIC_LDFLAGS -L$DEPS_PREFIX/lib -L$COMPRESSION_PREFIX/lib -L$expat/lib -L$ncurses/lib"
        run_make
        install_component_binary lftp src/lftp lftp
    )
}
