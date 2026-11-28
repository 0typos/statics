#!/usr/bin/env bash

# The C library tcc compiles against: musl's headers, start files, and
# libc.a for this target, built from the pinned release rather than taken
# from Zig's copy, so the archive's sources.lock names what it holds.
build_tcc_musl() {
    echo "==> building musl for tcc"
    (
        cd "$WORK_DIR/musl" || exit
        # tcc's RISC-V linker has no absolute HI20/LO12 relocations, which
        # is what clang's default code model (medlow) addresses data with;
        # medany uses the PC-relative ones it does have.
        local cflags=-Os
        [[ $STATICS_ARCH != riscv64 ]] || cflags+=' -mcmodel=medany'
        # CROSS_COMPILE is empty because the wrappers already carry the
        # target; configure would otherwise look for TARGET-ar.
        CC="$CC" AR="$AR" RANLIB="$RANLIB" CROSS_COMPILE='' ./configure \
            --target="$AUTOCONF_HOST" \
            --prefix=/ \
            --disable-shared \
            CFLAGS="$cflags"
        run_make
        make -s install DESTDIR="$PWD/install"
        # COPYRIGHT says which parts are BSD-licensed but leaves the terms
        # in the source files; libc.a holds that code, so gather them.
        local file
        grep -rl 'Redistribution and use' src | LC_ALL=C sort > bsd-files
        [[ -s bsd-files ]] || {
            echo "musl: found no BSD-licensed source files" >&2
            exit 1
        }
        while IFS= read -r file; do
            printf '%s\n\n' "$file"
            sed -n '1,/\*\//p' "$file"
            echo
        done < bsd-files > MUSL-BSD-NOTICES
    )
}

build_tcc() {
    echo "==> building tcc"
    (
        cd "$WORK_DIR/tcc" || exit
        patch -s -p1 < "$REPO_ROOT/patches/tcc-relocatable.patch"
        patch -s -p1 < "$REPO_ROOT/patches/tcc-no-run.patch"
        local destination
        destination=$(archive_dir tcc) || exit
        local runtime=$destination/lib/tcc

        # Everything tcc needs sits under {B}, the lib/tcc beside it: its
        # own headers and libtcc1.a, and musl in musl/. -static is a
        # built-in switch because the kit has no dynamic loader to name,
        # and the bounds checker (-b) is left out because it cannot
        # interpose malloc in a static program.
        # The ARM targets are both EABI hard float, which configure reads
        # off the triplet. --cross-prefix makes configure treat every
        # build as a cross build: otherwise, where the builder can run the
        # target, it probes the builder's /usr/lib and /proc/cpuinfo.
        # --os-release keeps the builder's kernel version out of config.h.
        local options=(
            --cpu="$STATICS_TCC_CPU"
            --triplet="$AUTOCONF_HOST"
            --config-musl
            --config-bcheck=no
            --os-release=0
            --tccdir=/usr/lib/tcc
            --sysincludepaths='{B}/include:{B}/musl/include'
            --libpaths='{B}:{B}/musl/lib'
            --crtprefix='{B}/musl/lib'
            --tcc-switches=-static
        )
        # In the source tree: lib/Makefile cannot find bcheck.c from a
        # separate build directory.
        ./configure "${options[@]}" \
            --cross-prefix="$REPO_ROOT/scripts/toolchain/" --cc=cc --ar=ar \
            --extra-cflags="$STATIC_CFLAGS" \
            --extra-ldflags="$STATIC_LDFLAGS" >/dev/null
        # The Makefile would compile this generator of tccdefs_.h for the
        # target and then run it.
        cc -DC2STR conftest.c -o c2str.exe
        # GITHASH=no: the Makefile would otherwise ask git, where there is
        # one, for a branch and date to put in `tcc -v`.
        run_make tcc GITHASH=no
        install_component_binary tcc tcc tcc

        mkdir -p "$runtime/include" "$runtime/musl"
        install -m 0644 include/*.h tcclib.h "$runtime/include/"
        cp -R "$WORK_DIR/musl/install/include" "$WORK_DIR/musl/install/lib" "$runtime/musl/"

        # libtcc1.a and the -bt support objects are compiled
        # by tcc itself. The one just built runs only on the target, so
        # build the same configuration from a second copy of the source
        # with the builder's compiler, and let that one compile them
        # against the runtime directory staged above.
        cp -a "$SOURCES_DIR/tcc" host
        (
            cd host || exit
            ./configure "${options[@]}" \
                --cross-prefix=/usr/bin/ --cc=cc --ar=ar >/dev/null
            run_make tcc GITHASH=no
        )
        run_make -C lib XTCC="$PWD/host/tcc" XFLAGS-unx="-B$runtime"
        install -m 0644 libtcc1.a "$runtime/"
        # runmain.o stays behind: it serves only -run, which is patched out.
        install -m 0644 bt-exe.o bt-log.o "$runtime/"

        # libtcc1.a is linked into every program tcc builds, and parts of
        # it are not under tcc's LGPL: gather each part's own notice, and
        # the license texts those notices name but the tcc tree lacks.
        local part
        for part in lib/libtcc1.c lib/atomic.S lib/armeabi.c lib/lib-arm64.c \
            include/stdatomic.h; do
            printf '%s\n\n' "$part"
            # Through the end of the comment that states the terms.
            awk '{ print }
                /SPDX-License-Identifier|General Public License|Permission is hereby granted|Copying and distribution/ { seen = 1 }
                seen && /\*\// { exit }' "$part"
            echo
        done > TCC-RUNTIME-NOTICES
        [[ $(grep -c 'GCC-exception-3.1\|unlimited permission to link\|Permission is hereby granted\|Copying and distribution of this file\|LLVM-exception' \
            TCC-RUNTIME-NOTICES) -ge 5 ]] || {
            echo "tcc: a runtime notice is missing from TCC-RUNTIME-NOTICES" >&2
            exit 1
        }
        cp "$SOURCES_DIR/binutils/COPYING" COPYING.GPL-2.0
        cp "$SOURCES_DIR/binutils/COPYING3" COPYING.GPL-3.0
        cp "$REPO_ROOT/configs/GCC-exception-3.1.txt" COPYING.GCC-exception-3.1
        find "$runtime" -type d -exec chmod 0755 {} +
        find "$runtime" -type f -exec chmod 0644 {} +
    )
}
