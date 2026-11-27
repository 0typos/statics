#!/usr/bin/env bash

build_lua() {
    echo "==> building lua"
    (
        cd "$WORK_DIR/lua" || exit
        # The interpreter only, no luac. LUA_USE_POSIX rather than
        # LUA_USE_LINUX: no dlopen for C modules in a static program, and
        # no readline, so the prompt has no line editing.
        run_make -C src lua \
            CC="$CC" AR="$AR rcu" RANLIB="$RANLIB" \
            SYSCFLAGS=-DLUA_USE_POSIX \
            MYCFLAGS="$STATIC_CFLAGS" \
            MYLDFLAGS="$STATIC_LDFLAGS"
        install_component_binary lua src/lua lua
        # The archive's only license text is the notice that ends lua.h.
        sed -n '/^\* Copyright (C) .* Lua\.org, PUC-Rio\./,/^\*\{20,\}\//p' \
            src/lua.h > LUA-LICENSE
        grep -q 'Permission is hereby granted' LUA-LICENSE || {
            echo "LUA-LICENSE lacks lua.h's notice" >&2
            exit 1
        }
    )
}
