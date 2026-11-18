#!/usr/bin/env bash

build_hping3() {
    echo "==> building hping3 (with Debian's patch set)"
    (
        cd "$WORK_DIR/hping3" || exit
        # Upstream stopped in 2005; Debian's patches are the maintained
        # line: portable byte order, libpcap 0.8+, Tcl optional, and bug
        # fixes. Applied in Debian's order.
        local debian=$WORK_DIR/hping3-debian name
        while read -r name; do
            [[ -z $name || $name == \#* ]] && continue
            patch -s -p1 < "$debian/patches/$name"
        done < "$debian/patches/series"
        patch -s -p1 < "$REPO_ROOT/patches/hping3-overflows.patch"
        # configure is a shell script that compiles and runs byteorder.c to
        # learn the byte order. Run it with the host compiler, which only
        # writes the Makefile and headers, then replace byteorder.h with the
        # target's byte order from the compiler. No Tcl scripting.
        CC=cc ./configure --no-tcl
        cat > byteorder.h <<'EOF'
#ifndef __BYTEORDER_H
#define __BYTEORDER_H
#if __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
#define __BIG_ENDIAN_BITFIELD
#else
#define __LITTLE_ENDIAN_BITFIELD
#endif
#endif
EOF
        # The link rule then runs the new binary; drop that line.
        grep -q '^	\./hping3 -v$' Makefile || {
            echo "hping3 Makefile no longer runs ./hping3 -v" >&2
            exit 1
        }
        sed -i '/^	\.\/hping3 -v$/d' Makefile
        run_make hping3 CC="$CC" AR="$AR" RANLIB="$RANLIB" \
            CCOPT="$STATIC_CFLAGS -I$DEPS_PREFIX/include" DEBUG= \
            prefix="$DEPS_PREFIX" LDFLAGS="$STATIC_LDFLAGS"
        install_binary hping3 hping3
        # COPYING is the GPLv2 and names the exceptions, whose terms are in
        # their header comments: display_ipopt.c (BSD-4-Clause-UC, from
        # ping) and strlcpy.c (BSD-3-Clause).
        local file
        for file in display_ipopt.c strlcpy.c; do
            echo "$file:"
            awk '/^ \* Copyright \(c\)/ { c = 1 } c { print } c && /\*\// { exit }' "$file"
            echo
        done > HPING3-NOTICES
        grep -q 'advertising materials' HPING3-NOTICES || {
            echo "HPING3-NOTICES lacks the display_ipopt.c notice" >&2
            exit 1
        }
    )
}
