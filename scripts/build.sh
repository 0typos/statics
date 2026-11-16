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

IFS='|' read -r _ zig_target zig_cpu _ _ go_env <<<"$record"

export REPO_ROOT=$repo_root
export SOURCES_DIR=${SOURCES_DIR:-/src}
export WORK_DIR=${BUILD_DIR:-/build}/"$arch"
export OUTPUT_DIR=$output_dir
# Components marked `extra` in components.tsv install here and are packaged
# as statics-extra-<arch>.tar.xz; the directory exists only when one does.
export EXTRA_OUTPUT_DIR=$output_dir-extra
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
# Every build gets its own cold Zig cache. Zig does not replay compiler
# warnings on a cache hit, and configure scripts that accept a flag only when
# a probe compiles silently (ldns) then reach different results from a warm
# cache: a second build in the same cache produced a different drill.
export ZIG_GLOBAL_CACHE_DIR="$WORK_DIR/zig-cache/global"
export ZIG_LOCAL_CACHE_DIR="$WORK_DIR/zig-cache/local"
# Per-component hang guard in seconds (run-builder.sh); empty disables it.
export STATICS_COMPONENT_TIMEOUT=${STATICS_COMPONENT_TIMEOUT:-}
if [[ -n $STATICS_COMPONENT_TIMEOUT && ! $STATICS_COMPONENT_TIMEOUT =~ ^[0-9]+$ ]]; then
    echo "STATICS_COMPONENT_TIMEOUT must be whole seconds: $STATICS_COMPONENT_TIMEOUT" >&2
    exit 2
fi
export STATICS_ARCH=$arch
# Go tools build only where architectures.tsv gives a Go environment.
# Everything that could reach the network or a host setting is pinned off:
# modules come from the cache the sources stage filled (GOPROXY=off), go.sum
# must already cover them (-mod=readonly), and a go.mod asking for a newer Go
# fails instead of downloading one (GOTOOLCHAIN=local).
if [[ $go_env != none ]]; then
    for setting in $go_env; do
        [[ $setting =~ ^GO[A-Z0-9]+=[a-z0-9.,]+$ ]] || {
            echo "invalid Go setting for $arch: $setting" >&2
            exit 2
        }
        export "${setting?}"
    done
    # Go accepts only absolute cache paths.
    GOMODCACHE=$(realpath -m "$SOURCES_DIR/go-modules")
    GOCACHE=$(realpath -m "$WORK_DIR/go-cache")
    GOPATH=$(realpath -m "$WORK_DIR/go-path")
    export GOOS=linux CGO_ENABLED=0 GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off \
        GOWORK=off GOENV=off GOFLAGS='-mod=readonly -trimpath -buildvcs=false' \
        GOMODCACHE GOCACHE GOPATH
fi
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
    ppp
    picocom
    lrzsz
    gdb
    openssh
    libnfnetlink
    libnetfilter_conntrack
    conntrack-tools
    ipmitool
    mtd-utils
    libnl
    iw
    wireguard-go
)

for path in "$WORK_DIR" "$OUTPUT_DIR" "$EXTRA_OUTPUT_DIR"; do
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

rm -rf "$WORK_DIR" "$OUTPUT_DIR" "$EXTRA_OUTPUT_DIR"
mkdir -p "$WORK_DIR" "$OUTPUT_DIR" "$DEPS_PREFIX"

# Autoconf decides it is cross compiling only when its test binary fails to
# run. With QEMU registered in binfmt_misc, which CI does to verify and many
# dev hosts have, a foreign test binary runs, configure starts executing
# target probes under emulation, and both its results and the artifacts
# change; one of curl's probes spun forever under qemu-mips on CircleCI. For
# targets this host cannot run natively, say so up front. Builders that set
# their own CONFIG_SITE (nmap) also pass --build, which has the same effect.
case "$(uname -m):$arch" in
    x86_64:x86_64 | x86_64:i686 | aarch64:aarch64)
        ;;
    *)
        printf 'cross_compiling=yes\n' >"$WORK_DIR/config.site"
        export CONFIG_SITE="$WORK_DIR/config.site"
        ;;
esac

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
        e2fsprogs smartmontools libnvme nvme-cli ppp tunpipe picocom lrzsz gdb \
        sftp-server libnfnetlink libnetfilter_conntrack conntrack ipmitool \
        mtd-utils libnl iw; do
        printf ' $(S)/%s' "$c"
    done
    if [[ $go_env != none ]]; then
        printf ' $(S)/%s' wireguard-go
    fi
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
    emit ppp ppp build_ppp
    emit tunpipe tunpipe build_tunpipe
    emit picocom picocom build_picocom
    emit lrzsz lrzsz build_lrzsz
    emit gdb gdb build_gdbserver
    emit sftp-server openssh build_sftp_server
    emit libnfnetlink conntrack build_libnfnetlink deps
    emit libnetfilter_conntrack conntrack build_libnetfilter_conntrack deps libnfnetlink
    emit conntrack conntrack build_conntrack libnetfilter_conntrack
    emit ipmitool ipmitool build_ipmitool deps
    emit mtd-utils mtd-utils build_mtd_utils
    emit libnl iw build_libnl deps
    emit iw iw build_iw libnl
    emit wireguard-go wireguard-go build_wireguard_go
} > "$dag"

if ! make -f "$dag" -j"$JOBS" --output-sync=target all; then
    if [[ -f $WORK_DIR/.hung && -z ${STATICS_RESTARTED:-} ]]; then
        echo "==> a component hung; rebuilding $arch once from a clean tree" >&2
        STATICS_RESTARTED=1 exec "$repo_root/scripts/build.sh" "$arch" "$output_dir"
    fi
    exit 1
fi

# Write the metadata of one archive: BUILDINFO, SHA256SUMS, sources.lock,
# licenses and notices for exactly its components, and its SBOM.
finish_archive() { # directory archive
    local dir=$1 archive=$2
    {
        echo "architecture=$arch"
        echo "archive=$archive"
        echo "zig_target=$ZIG_TARGET"
        echo "zig_cpu=$ZIG_CPU"
        echo "autoconf_host=$AUTOCONF_HOST"
        echo "zig_version=$("$ZIG" version)"
        if [[ $go_env != none ]]; then
            echo "go_version=$(go env GOVERSION)"
            echo "go_env=$go_env"
        fi
        # Inside the Docker builder, record the host toolchain too: autotools,
        # perl, and python shape the output, so their versions are an input.
        apt_sources=/etc/apt/sources.list.d/debian.sources
        if grep -q '^URIs: http://snapshot\.debian\.org/' "$apt_sources" 2>/dev/null &&
            command -v dpkg-query >/dev/null; then
            echo "debian_snapshot=$(grep -m 1 -oE '[0-9]{8}T[0-9]{6}Z' "$apt_sources")"
            echo "debian_packages_sha256=$(dpkg-query -W -f '${Package}=${Version}\n' |
                LC_ALL=C sort | sha256sum | cut -d ' ' -f 1)"
        fi
        echo "libc=musl"
        echo "source_date_epoch=$SOURCE_DATE_EPOCH"
        echo
        awk -F '|' '$0 !~ /^#/ { printf "%s=%s\n", $1, $2 }' "$repo_root/sources.lock"
    } > "$dir/BUILDINFO"

    (
        cd "$dir"
        find . -type f \
            \( -perm /111 -o -path './share/nmap/*' \) \
            -printf '%P\n' |
            LC_ALL=C sort |
            xargs -r sha256sum > SHA256SUMS
    )

    cp "$repo_root/sources.lock" "$dir/sources.lock"
    "$repo_root/scripts/collect-licenses.sh" "$WORK_DIR" "$dir" "$arch" "$archive"
    python3 "$repo_root/scripts/generate-sbom.py" "$dir" "$arch" "$archive"
    echo "==> built $arch $archive archive in $dir"
}

finish_archive "$OUTPUT_DIR" main
# An extra archive exists only when this architecture builds an extra tool.
if [[ -n $("$repo_root/scripts/components.sh" "$arch" extra) ]]; then
    finish_archive "$EXTRA_OUTPUT_DIR" extra
elif [[ -e $EXTRA_OUTPUT_DIR ]]; then
    echo "$EXTRA_OUTPUT_DIR exists, but components.tsv puts nothing in $arch's extra archive" >&2
    exit 1
fi
