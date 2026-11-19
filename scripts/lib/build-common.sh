#!/usr/bin/env bash

export STATIC_CFLAGS='-Os -ffunction-sections -fdata-sections'
export STATIC_LDFLAGS='-static -Wl,--gc-sections -Wl,-s'

# Component builds run under one top-level GNU make jobserver (see
# scripts/build.sh), which enforces a single global parallelism budget across
# every component and its inner make. An explicit -j here would opt out of the
# jobserver and multiply the budget, so pass -j only when no jobserver exists
# (a builder invoked directly, outside the DAG).
run_make() {
    if [[ ${MAKEFLAGS-} == *jobserver* ]]; then
        make -s "$@"
    else
        make -s -j"$JOBS" "$@"
    fi
}

# A meson cross file for this target, for the meson-built components.
meson_cross_file() {
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

install_binary() {
    local source=$1
    local destination=$2
    install -m 0755 "$source" "$OUTPUT_DIR/$destination"
}

install_output_file() {
    local source=$1
    local destination=$2
    install -D -m 0644 "$source" "$OUTPUT_DIR/$destination"
}

install_dependency_file() {
    local source=$1
    local destination=$2
    install -D -m 0644 "$source" "$DEPS_PREFIX/$destination"
}

# The output directory of the archive components.tsv names for COMPONENT
# (main or extra), created on demand.
archive_dir() { # component
    local archive
    archive=$(awk -F '|' -v wanted="$1" '$0 !~ /^#/ && $1 == wanted { print $4 }' \
        "$REPO_ROOT/components.tsv")
    case $archive in
        main) echo "$OUTPUT_DIR" ;;
        extra) mkdir -p "$EXTRA_OUTPUT_DIR" && echo "$EXTRA_OUTPUT_DIR" ;;
        *)
            echo "$1 has no main or extra archive in components.tsv" >&2
            return 1
            ;;
    esac
}

# Install a C tool's executable into its component's archive.
install_component_binary() { # component source destination
    local directory
    directory=$(archive_dir "$1") || return 1
    install -m 0755 "$2" "$directory/$3"
}

make_link() {
    local target=$1
    local link_name=$2
    ln -s "$target" "$OUTPUT_DIR/$link_name"
}

# The pinned version of one sources.lock entry, for version strings that
# upstream sets at link time.
source_version() { # name
    awk -F '|' -v wanted="$1" '$0 !~ /^#/ && $1 == wanted { print $2 }' \
        "$REPO_ROOT/sources.lock"
}

# Build one Go main package of COMPONENT into the archive components.tsv
# names for it, as a stripped static binary (the hermetic Go environment is
# set by scripts/build.sh), with the build flags (such as -tags=...) listed
# before its packages in components.tsv, which the module fetch uses too, and
# any extra linker flags (such as -X for a version). Then stage, for
# collect-licenses.sh, the module list from the binary's own build info and
# every module's license files.
go_build() { # component package binary [ldflag...]
    local component=$1 package=$2 binary=$3
    shift 3
    local destination packages word flags=()
    packages=$(awk -F '|' -v wanted="$component" \
        '$0 !~ /^#/ && $1 == wanted { print $5 }' "$REPO_ROOT/components.tsv")
    for word in $packages; do
        [[ $word == -* ]] && flags+=("$word")
    done
    destination=$(archive_dir "$component") || return 1
    (
        cd "$WORK_DIR/$component" &&
            go build "${flags[@]}" -ldflags="-s -w -buildid= $*" \
                -o "$destination/$binary" "$package"
    ) || return 1

    local staged="$WORK_DIR/go-licenses/$component"
    mkdir -p "$staged/modules"
    # `dep PATH VERSION SUM`, each optionally followed by its `=> PATH VERSION
    # SUM` replacement, whose files are the ones linked.
    go version -m "$destination/$binary" | awk '
        $1 == "dep" { if (line) print line; line = $2 "|" $3 "|" $4 }
        $1 == "=>" { line = $2 "|" $3 "|" $4 }
        END { if (line) print line }
    ' >>"$staged/go-modules.tsv" || return 1
    LC_ALL=C sort -u -o "$staged/go-modules.tsv" "$staged/go-modules.tsv"

    local path version _sum source found file
    while IFS='|' read -r path version _sum; do
        # The module cache spells capitals as ! plus the lowercase letter.
        # shellcheck disable=SC2001  # needs \L, which ${//} lacks
        source="$GOMODCACHE/$(sed 's/[A-Z]/!\L&/g' <<<"$path@$version")"
        found=
        for file in "$source"/*; do
            [[ -f $file ]] || continue
            case ${file##*/} in
                [Ll][Ii][Cc][Ee][Nn][CcSs][Ee]* | [Cc][Oo][Pp][Yy][Ii][Nn][Gg]* | \
                    [Nn][Oo][Tt][Ii][Cc][Ee]*)
                    found=1
                    ;;
                # A patent grant travels with the license but is not one.
                PATENTS*) ;;
                *) continue ;;
            esac
            install -D -m 0644 "$file" "$staged/modules/$path@$version/${file##*/}"
        done
        [[ $found ]] || {
            echo "Go module $path@$version in $binary has no license file in $source" >&2
            return 1
        }
    done <"$staged/go-modules.tsv"
}
