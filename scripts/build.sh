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

source "$repo_root/scripts/lib/build-common.sh"
source "$repo_root/scripts/builders/dependencies.sh"
source "$repo_root/scripts/builders/busybox.sh"
source "$repo_root/scripts/builders/socat.sh"
source "$repo_root/scripts/builders/dropbear.sh"
source "$repo_root/scripts/builders/iproute2.sh"
source "$repo_root/scripts/builders/wireguard-tools.sh"
source "$repo_root/scripts/builders/tcpdump.sh"
source "$repo_root/scripts/builders/curl.sh"
source "$repo_root/scripts/builders/iperf3.sh"
source "$repo_root/scripts/builders/ethtool.sh"
source "$repo_root/scripts/builders/strace.sh"
source "$repo_root/scripts/builders/jq.sh"
source "$repo_root/scripts/builders/ldns.sh"
source "$repo_root/scripts/builders/mtr.sh"
source "$repo_root/scripts/builders/can-utils.sh"
source "$repo_root/scripts/builders/i2c-tools.sh"
source "$repo_root/scripts/builders/spi-tools.sh"
source "$repo_root/scripts/builders/nmap.sh"
source "$repo_root/scripts/builders/rsync.sh"
source "$repo_root/scripts/builders/lsof.sh"

build_dependencies
build_strace
build_tcpdump
build_curl
build_iperf3
build_ethtool
build_jq
build_ldns
build_mtr
build_can_utils
build_i2c_tools
build_spi_tools
build_nmap
build_rsync
build_lsof
build_busybox
build_socat
build_dropbear
build_iproute2
build_wireguard_tools

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
