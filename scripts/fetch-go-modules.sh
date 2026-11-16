#!/usr/bin/env bash
# Download the Go modules each Go tool's main packages import, for every
# GOARCH in architectures.tsv, into SOURCES_DIR/go-modules (a GOMODCACHE),
# and copy the downloaded archives to BUNDLE_DIR in GOPROXY layout.
#
# Only modules that the packages import on linux are fetched, not the whole
# go.mod graph. -mod=readonly makes go.sum, pinned with its source archive
# in sources.lock, the authority: a module missing from it or hashing
# differently fails here. The build then runs with GOPROXY=off against this
# cache; GOPROXY=file://BUNDLE_DIR rebuilds from the source bundle.
#
# Usage: fetch-go-modules.sh SOURCES_DIR BUNDLE_DIR
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [[ $# -ne 2 ]]; then
    echo "usage: $0 SOURCES_DIR BUNDLE_DIR" >&2
    exit 2
fi

# Go accepts only absolute cache paths.
sources_dir=$(realpath -m "$1")
bundle_dir=$2

export GOMODCACHE="$sources_dir/go-modules"
GOCACHE=$(mktemp -d)
export GOCACHE
trap 'rm -rf "$GOCACHE"' EXIT
export CGO_ENABLED=0 GOOS=linux GOTOOLCHAIN=local GOWORK=off GOENV=off
export GOFLAGS=-mod=readonly GOPROXY=https://proxy.golang.org GOSUMDB=sum.golang.org

goarches=$(awk -F '|' '$0 !~ /^#/ && NF {
    for (i = split($6, kv, " "); i > 0; i--)
        if (kv[i] ~ /^GOARCH=/) print substr(kv[i], 8)
}' "$repo_root/architectures.tsv" | sort -u)

found=
while IFS='|' read -r name _ _ _ packages; do
    [[ $name == \#* || -z $name || $packages == - || $packages == runtime ]] && continue
    found=1
    for goarch in $goarches; do
        echo "==> Go modules for $name ($goarch)"
        # shellcheck disable=SC2086  # packages is a space-separated list
        (cd "$sources_dir/$name" && GOARCH=$goarch go list -deps $packages >/dev/null)
    done
done < "$repo_root/components.tsv"

[[ $found ]] || exit 0
mkdir -p "$bundle_dir"
cp -R "$GOMODCACHE/cache/download/." "$bundle_dir/"
# Lock files are empty download coordination, not module content.
find "$bundle_dir" -name '*.lock' -delete
chmod -R u+w,a+rX "$bundle_dir"
