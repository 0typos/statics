#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "usage: $0 ARCH [OUTPUT_DIR]" >&2
    exit 2
fi

arch=$1
output_dir=${2:-"$repo_root/dist/$arch"}
record=$(awk -F '|' -v wanted="$arch" '
    $0 !~ /^#/ && $1 == wanted { print; found++ }
    END { if (found != 1) exit 1 }
' "$repo_root/architectures.tsv") || {
    echo "unknown or duplicated architecture: $arch" >&2
    exit 2
}

IFS='|' read -r _ zig_target zig_cpu _ _ <<<"$record"

export REPO_ROOT=$repo_root
export SOURCES_DIR=${SOURCES_DIR:-/src}
export WORK_DIR=${BUILD_DIR:-/build}/"$arch"
export OUTPUT_DIR=$output_dir
export DEPS_PREFIX="$WORK_DIR/prefix"
export ZIG=${ZIG:-zig}
export ZIG_TARGET=$zig_target
export ZIG_CPU=$zig_cpu
export AUTOCONF_HOST=$zig_target
if [[ $arch == i686 ]]; then
    AUTOCONF_HOST=i686-linux-musl
fi
export CC="$repo_root/scripts/toolchain/cc"
export CXX="$repo_root/scripts/toolchain/cxx"
export AR="$repo_root/scripts/toolchain/ar"
export RANLIB="$repo_root/scripts/toolchain/ranlib"
export JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN)}
export STATICS_ARCH=$arch
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-0}
export KCONFIG_NOTIMESTAMP=1
export TZ=UTC
export LC_ALL=C

case "$arch" in
    i686|armv6-hardfloat|armv7-hardfloat|armv7-softfloat|\
        mips|mipsel|powerpc)
        export TARGET_BITS=32
        export OPENSSL_THREAD_OPTION=no-threads
        ;;
    *)
        export TARGET_BITS=64
        export OPENSSL_THREAD_OPTION=
        ;;
esac

sources=(
    busybox
    socat
    dropbear
    iproute2
    wireguard-tools
    openssl
    libpcap
    libmnl
    libcap-ng
    libnftnl
    nftables
    tcpdump
    curl
    iperf3
    ethtool
    strace
    jq
    ldns
    mtr
    can-utils
    i2c-tools
    spi-tools
    nmap
    rsync
    lsof
    util-linux
    e2fsprogs
    smartmontools
    libnvme
    nvme-cli
)

for path in "$WORK_DIR" "$OUTPUT_DIR"; do
    case "$path" in
        ""|/|"$repo_root")
            echo "refusing unsafe build path: $path" >&2
            exit 2
            ;;
    esac
done

for source in "${sources[@]}"; do
    if [[ ! -d $SOURCES_DIR/$source ]]; then
        echo "missing source tree: $SOURCES_DIR/$source" >&2
        exit 1
    fi
done

rm -rf "$WORK_DIR" "$OUTPUT_DIR"
mkdir -p "$WORK_DIR" "$OUTPUT_DIR" "$DEPS_PREFIX"

for source in "${sources[@]}"; do
    mkdir "$WORK_DIR/$source"
    cp -a "$SOURCES_DIR/$source/." "$WORK_DIR/$source/"
done

# Components build as a GNU make DAG under one jobserver: `make -j$JOBS` is
# the single global parallelism budget, shared between concurrently building
# components and their inner makes (builders call run_make, which defers to
# the jobserver instead of stacking its own -j). Library deps build serially
# into the shared prefix first; everything else parallelizes against the DAG.
stamps=$WORK_DIR/.stamps
mkdir -p "$stamps"

dag=$WORK_DIR/dag.mk
# shellcheck disable=SC2016  # $(S)/$(RB) are make variables, not shell
{
    printf 'RB := %s/scripts/run-builder.sh\n' "$repo_root"
    printf 'S := %s\n\n' "$stamps"
    printf '.PHONY: all\n'
    printf 'all:'
    for c in deps libnftnl nftables strace tcpdump curl iperf3 ethtool jq \
        ldns mtr can-utils i2c-tools spi-tools nmap rsync lsof util-linux \
        busybox socat dropbear iproute2 wireguard-tools \
        e2fsprogs smartmontools libnvme nvme-cli; do
        printf ' $(S)/%s' "$c"
    done
    printf '\n\n'

    emit() { # target, builder file, function, prerequisites...
        local target=$1 file=$2 fn=$3
        shift 3
        printf '$(S)/%s:' "$target"
        local dep
        for dep in "$@"; do printf ' $(S)/%s' "$dep"; done
        printf '\n\t+@$(RB) %s %s && touch $@\n' "$file" "$fn"
    }

    emit deps dependencies build_dependencies
    emit libnftnl nftables build_libnftnl deps
    emit nftables nftables build_nftables libnftnl
    emit strace strace build_strace
    emit tcpdump tcpdump build_tcpdump deps
    emit curl curl build_curl deps
    emit iperf3 iperf3 build_iperf3 deps
    emit ethtool ethtool build_ethtool deps
    emit jq jq build_jq
    emit ldns ldns build_ldns deps
    emit mtr mtr build_mtr
    emit can-utils can-utils build_can_utils
    emit i2c-tools i2c-tools build_i2c_tools
    emit spi-tools spi-tools build_spi_tools
    emit nmap nmap build_nmap deps
    emit rsync rsync build_rsync
    emit lsof lsof build_lsof
    emit util-linux util-linux build_util_linux deps
    emit busybox busybox build_busybox
    emit socat socat build_socat deps
    emit dropbear dropbear build_dropbear
    emit iproute2 iproute2 build_iproute2 deps
    emit wireguard-tools wireguard-tools build_wireguard_tools
    emit e2fsprogs e2fsprogs build_e2fsprogs
    emit smartmontools smartmontools build_smartmontools
    emit libnvme nvme build_libnvme deps
    emit nvme-cli nvme build_nvme_cli libnvme
} > "$dag"

make -f "$dag" -j"$JOBS" --output-sync=target all

{
    echo "architecture=$arch"
    echo "zig_target=$ZIG_TARGET"
    echo "zig_cpu=$ZIG_CPU"
    echo "autoconf_host=$AUTOCONF_HOST"
    echo "zig_version=$("$ZIG" version)"
    echo "libc=musl"
    echo "source_date_epoch=$SOURCE_DATE_EPOCH"
    echo
    awk -F '|' '$0 !~ /^#/ { printf "%s=%s\n", $1, $2 }' "$repo_root/sources.lock"
} > "$OUTPUT_DIR/BUILDINFO"

(
    cd "$OUTPUT_DIR"
    find . -type f \
        \( -perm /111 -o -path './share/nmap/*' \) \
        -printf '%P\n' |
        LC_ALL=C sort |
        xargs -r sha256sum > SHA256SUMS
)

cp "$repo_root/sources.lock" "$OUTPUT_DIR/sources.lock"
"$repo_root/scripts/collect-licenses.sh" "$WORK_DIR" "$OUTPUT_DIR"
python3 "$repo_root/scripts/generate-sbom.py" "$OUTPUT_DIR" "$arch"
echo "==> built $arch in $OUTPUT_DIR"
