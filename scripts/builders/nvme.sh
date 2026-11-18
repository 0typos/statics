#!/usr/bin/env bash

# libnvme + nvme-cli build with meson, like kmod. Meson cannot join the make
# jobserver (ninja speaks a different protocol), so these components compile
# with their own bounded -j"$JOBS" — the only spots in the DAG that can
# briefly exceed the global budget, by at most one component's slice.

build_libnvme() {
    echo "==> building libnvme"
    (
        cd "$WORK_DIR/libnvme" || exit
        meson_cross_file cross.ini
        PKG_CONFIG_LIBDIR="$DEPS_PREFIX/lib/pkgconfig" \
        meson setup build \
            --cross-file cross.ini \
            --default-library=static \
            --prefer-static \
            --prefix="$DEPS_PREFIX" \
            --libdir=lib \
            --buildtype=plain \
            -Dc_args="$STATIC_CFLAGS" \
            -Dc_link_args="$STATIC_LDFLAGS" \
            -Dlibdbus=disabled \
            -Djson-c=disabled \
            -Dopenssl=disabled \
            -Dkeyutils=disabled \
            -Dliburing=disabled \
            -Dpython=disabled \
            -Ddocs=false \
            -Dtests=false \
            -Dexamples=false
        meson compile -C build -j "$JOBS"
        meson install -C build --quiet
    )
}

build_nvme_cli() {
    echo "==> building nvme-cli (nvme)"
    (
        cd "$WORK_DIR/nvme-cli" || exit
        meson_cross_file cross.ini
        PKG_CONFIG_LIBDIR="$DEPS_PREFIX/lib/pkgconfig" \
        meson setup build \
            --cross-file cross.ini \
            --default-library=static \
            --prefer-static \
            --buildtype=plain \
            -Dc_args="$STATIC_CFLAGS -I$DEPS_PREFIX/include" \
            -Dc_link_args="$STATIC_LDFLAGS -L$DEPS_PREFIX/lib" \
            -Djson-c=disabled \
            -Ddocs=false
        meson compile -C build -j "$JOBS"
        install_binary build/nvme nvme
    )
}
