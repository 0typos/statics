#!/usr/bin/env bash

# libnvme + nvme-cli build with meson. Meson cannot join the make jobserver
# (ninja speaks a different protocol), so these two components compile with
# their own bounded -j"$JOBS" — the only spot in the DAG that can briefly
# exceed the global budget, by at most one component's slice.

_meson_cross_file() {
    local out=$1 family endian
    case "$STATICS_ARCH" in
        x86_64)                family=x86_64;  endian=little ;;
        i686)                  family=x86;     endian=little ;;
        aarch64)               family=aarch64; endian=little ;;
        armv6-hardfloat|armv7-hardfloat|armv7-softfloat)
                               family=arm;     endian=little ;;
        mips)                  family=mips;    endian=big ;;
        mipsel)                family=mips;    endian=little ;;
        powerpc)               family=ppc;     endian=big ;;
        powerpc64)             family=ppc64;   endian=big ;;
        powerpc64le)           family=ppc64;   endian=little ;;
        riscv64)               family=riscv64; endian=little ;;
        s390x)                 family=s390x;   endian=big ;;
        *) echo "no meson cpu_family mapping for $STATICS_ARCH" >&2; exit 1 ;;
    esac
    cat > "$out" <<EOF
[binaries]
c = '$CC'
cpp = '$CXX'
ar = '$AR'
ranlib = '$RANLIB'
pkg-config = 'pkg-config'

[host_machine]
system = 'linux'
cpu_family = '$family'
cpu = '$family'
endian = '$endian'
EOF
}

build_libnvme() {
    echo "==> building libnvme"
    (
        cd "$WORK_DIR/libnvme" || exit
        _meson_cross_file cross.ini
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
        _meson_cross_file cross.ini
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
