#!/usr/bin/env bash

build_bash() {
    echo "==> building bash"
    (
        cd "$WORK_DIR/bash" || exit
        local ncurses=$WORK_DIR/ncurses/install
        # Interactive bash with its bundled readline and history, using the
        # static ncurses from build_ncurses for terminal descriptions. No
        # NLS, programmable completion, help builtin, or bash's own malloc
        # (musl's is used). Network redirections (/dev/tcp) and process
        # substitution stay: testssl.sh needs both. The answers below are
        # what configure's run-time probes find on Linux with musl; giving
        # them on every target keeps native and cross builds alike.
        CC="$CC" AR="$AR" RANLIB="$RANLIB" CC_FOR_BUILD=cc ./configure \
            --build="$(cc -dumpmachine)" \
            --host="$AUTOCONF_HOST" \
            --prefix=/usr \
            --disable-nls \
            --disable-progcomp \
            --disable-help-builtin \
            --without-bash-malloc \
            --with-curses \
            bash_cv_job_control_missing=present \
            bash_cv_sys_named_pipes=present \
            bash_cv_func_sigsetjmp=present \
            bash_cv_printf_a_format=yes \
            bash_cv_getcwd_malloc=yes \
            CPPFLAGS="-I$ncurses/include/ncurses -I$ncurses/include" \
            CFLAGS="$STATIC_CFLAGS" \
            LDFLAGS="$STATIC_LDFLAGS -L$ncurses/lib"
        run_make bash
        install_binary bash bash
    )
}
