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
    local record archive destination word flags=()
    record=$(awk -F '|' -v wanted="$component" \
        '$0 !~ /^#/ && $1 == wanted { print $4 "|" $5 }' "$REPO_ROOT/components.tsv")
    archive=${record%%|*}
    for word in ${record#*|}; do
        [[ $word == -* ]] && flags+=("$word")
    done
    case $archive in
        main) destination=$OUTPUT_DIR ;;
        extra) destination=$EXTRA_OUTPUT_DIR ;;
        *)
            echo "$component has no main or extra archive in components.tsv" >&2
            return 1
            ;;
    esac
    mkdir -p "$destination"
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
