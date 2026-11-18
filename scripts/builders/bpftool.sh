#!/usr/bin/env bash

build_bpftool() {
    echo "==> building bpftool"
    (
        cd "$WORK_DIR/bpftool" || exit
        patch -s -p1 < "$REPO_ROOT/patches/bpftool-no-gen.patch"
        cd src || exit
        local libelf=$WORK_DIR/elfutils/libelf
        # bpftool and its bundled libbpf, against the libelf from
        # build_libelf and zlib. No LLVM or libbfd JIT disassembler, no
        # libcrypto (program signing), no libcap, and no clang: so no BPF
        # skeletons, and `prog profile` and the PIDs in `prog show` are
        # unavailable. The patch drops `bpftool gen`. Neither the host's
        # pkg-config nor its kernel BTF may reach the build, and libelf has
        # no zstd, whatever a probe against COMPRESSION_PREFIX finds.
        run_make bpftool \
            CC="$CC" AR="$AR" HOSTCC=false \
            CLANG=false LLVM_CONFIG=false LLVM_STRIP=false \
            SKIP_LLVM=1 SKIP_LIBBFD=1 SKIP_CRYPTO=1 \
            NO_PKG_CONFIG=1 VMLINUX_BTF= VMLINUX_H= feature-libelf-zstd=0 \
            EXTRA_CFLAGS="$STATIC_CFLAGS -I$libelf -I$COMPRESSION_PREFIX/include" \
            EXTRA_LDFLAGS="$STATIC_LDFLAGS -L$libelf -L$COMPRESSION_PREFIX/lib"
        install_binary bpftool bpftool
    )
}
