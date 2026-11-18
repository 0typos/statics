#!/usr/bin/env bash

build_kmod() {
    echo "==> building kmod"
    (
        cd "$WORK_DIR/kmod" || exit
        meson_cross_file cross.ini
        # gzip, xz, and zstd modules through the static libraries in
        # COMPRESSION_PREFIX, linked rather than dlopened. No OpenSSL, so
        # modinfo reports that a module is signed (sig_id) but not its
        # signer, key, or hash. Like nvme-cli, meson runs its own bounded
        # ninja.
        PKG_CONFIG_LIBDIR="$COMPRESSION_PREFIX/lib/pkgconfig" \
        meson setup build \
            --cross-file cross.ini \
            --default-library=static \
            --prefer-static \
            --buildtype=plain \
            -Db_pie=false \
            -Dc_args="$STATIC_CFLAGS" \
            -Dc_link_args="$STATIC_LDFLAGS" \
            -Dzstd=enabled \
            -Dxz=enabled \
            -Dzlib=enabled \
            -Dopenssl=disabled \
            -Dtools=true \
            -Dmanpages=false \
            -Ddocs=false \
            -Dbashcompletiondir=no \
            -Dfishcompletiondir=no \
            -Dzshcompletiondir=no
        meson compile -C build -j "$JOBS" kmod:executable
        install_binary build/kmod kmod
        # kmod picks its tool from argv[0].
        local tool
        for tool in modinfo lsmod insmod rmmod modprobe depmod; do
            make_link kmod "$tool"
        done
    )
}
