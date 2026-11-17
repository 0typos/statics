#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [[ $# -ne 1 ]]; then
    echo "usage: $0 ARCH" >&2
    exit 2
fi

arch=$1

# Package one exported tree as NAME.tar.xz, with its SBOM and checksums.
package() { # directory name
    local directory=$1 name=$2
    local archive="$repo_root/dist/$name.tar.xz"
    local sbom="$repo_root/dist/$name.spdx.json"
    tar --sort=name \
        --mtime="@${SOURCE_DATE_EPOCH:-0}" \
        --owner=0 --group=0 --numeric-owner \
        --create --xz --file "$archive" \
        --directory "$repo_root/dist" "$directory"
    cp "$repo_root/dist/$directory/SBOM.spdx.json" "$sbom"
    (
        cd "$repo_root/dist"
        sha256sum "$name.tar.xz" > "$name.tar.xz.sha256"
        sha256sum "$name.spdx.json" > "$name.spdx.json.sha256"
    )
    echo "$archive"
}

[[ -d $repo_root/dist/$arch ]] || {
    echo "build output not found: $repo_root/dist/$arch" >&2
    exit 1
}
package "$arch" "statics-$arch"
# The extra archive exists only for an architecture that builds an extra tool.
rm -f "$repo_root/dist/statics-extra-$arch".*
if [[ -d $repo_root/dist/$arch-extra ]]; then
    package "$arch-extra" "statics-extra-$arch"
fi
