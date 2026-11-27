#!/usr/bin/env bash

build_quickjs() {
    echo "==> building quickjs"
    (
        cd "$WORK_DIR/quickjs" || exit
        patch -s -p1 < "$REPO_ROOT/patches/quickjs-source-repl.patch"
        # qjs with the std, os, and bjson modules, compiled directly: the
        # sources and flags of upstream's CMake qjs target (-funsigned-char
        # is required), with the patch's embedded-js.c in place of the
        # little-endian bytecode in gen/. No qjsc; `qjs -c` makes
        # standalone programs.
        # shellcheck disable=SC2086  # flag lists
        "$CC" $STATIC_CFLAGS -w -funsigned-char -D_GNU_SOURCE -DQJS_BUILD_LIBC \
            $STATIC_LDFLAGS -o qjs \
            qjs.c embedded-js.c quickjs.c quickjs-libc.c libregexp.c \
            libunicode.c dtoa.c -lm -lpthread
        install_component_binary quickjs qjs qjs
    )
}
