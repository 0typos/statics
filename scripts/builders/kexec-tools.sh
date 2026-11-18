#!/usr/bin/env bash

build_kexec_tools() {
    echo "==> building kexec-tools (kexec)"
    (
        cd "$WORK_DIR/kexec-tools" || exit
        patch -s -p1 < "$REPO_ROOT/patches/kexec-tools-purgatory-map.patch"
        # On 32-bit PowerPC, kexec-ppc.c steps a pointer by assigning an
        # unsigned long long * to an unsigned long *: a GCC warning that
        # clang makes an error. The assignment converts as intended.
        local cflags=$STATIC_CFLAGS
        [[ $STATICS_ARCH == powerpc ]] && cflags+=' -Wno-error=incompatible-pointer-types'
        # zlib only, for gzip-compressed kernels (arm64 and RISC-V Image.gz,
        # gzip EFI zboot): 30 KB of the archive. liblzma and libzstd would
        # add 29 and 45 KB for rarer kernels; decompress those with the
        # bundled xz or zstd first. No Xen.
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --host="$AUTOCONF_HOST" \
            --with-zlib \
            --without-lzma \
            --without-zstd \
            --without-xen \
            CPPFLAGS="-I$COMPRESSION_PREFIX/include" \
            CFLAGS="$cflags" \
            LDFLAGS="$STATIC_LDFLAGS -L$COMPRESSION_PREFIX/lib"
        # configure only notes a missing zlib and builds without it.
        grep -q '^#define HAVE_LIBZ 1' include/config.h || {
            echo "kexec-tools did not find zlib" >&2
            exit 1
        }
        # Upstream strips the purgatory's debug sections with `strip
        # --strip-debug -o OUT IN`, but the host's strip cannot read foreign
        # ELF and zig objcopy only native-endian executables. Compile it
        # with -g0 instead (zig cc adds debug info to its assembly and -O2
        # objects) and copy it.
        # shellcheck disable=SC2016  # $3 and $4 are the script's arguments
        printf '#!/bin/sh\ncp "$4" "$3"\n' > copy-strip
        chmod +x copy-strip
        # Upstream's purgatory flags are for GCC. zig cc misparses x86-64's
        # -march=x86-64 (the cc wrapper already sets the CPU) and rejects
        # PowerPC's -msoft-float and ELFv1 -mcall-aixdesc. musl's ppc64 is
        # ELFv2 in both byte orders, which kexec-tools keys on _CALL_ELF
        # rather than byte order. -msoft-float kept floating-point and vector
        # registers out of the purgatory; for its integer code, compiling for
        # the generic ppc and ppc64 CPUs does too (checked by disassembly:
        # the POWER8 baseline copies structures with VSX).
        local purgatory=(
            x86_64_PURGATORY_EXTRA_CFLAGS='-mcmodel=large -mno-mmx -mno-sse -mno-sse2 -mno-avx'
            ppc64_PURGATORY_EXTRA_CFLAGS='-mcpu=ppc64 -fno-exceptions'
            ppc_PURGATORY_EXTRA_CFLAGS=
        )
        run_make build/sbin/kexec TARGET_CC="$CC -g0" STRIP="$PWD/copy-strip" \
            "${purgatory[@]}"
        install_binary build/sbin/kexec kexec
        # COPYING is the GPL; these files carry their own terms in their
        # header comments: libfdt (GPL-2.0-or-later OR BSD-2-Clause), the
        # Multiboot 2 header (MIT), and glibc's elf.h (LGPL-2.0-or-later).
        local file
        for file in kexec/libfdt/fdt.c include/x86/multiboot2.h include/elf.h; do
            echo "$file:"
            awk '{ print } /Copyright/ { c = 1 } c && /\*\// { exit }' "$file"
            echo
        done > KEXEC-TOOLS-NOTICES
        grep -q 'Permission is hereby granted' KEXEC-TOOLS-NOTICES || {
            echo "KEXEC-TOOLS-NOTICES lacks the Multiboot 2 MIT notice" >&2
            exit 1
        }
    )
}
