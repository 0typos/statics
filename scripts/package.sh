#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [[ $# -ne 1 ]]; then
    echo "usage: $0 ARCH" >&2
    exit 2
fi

arch=$1

# Package one exported tree as NAME.tar.xz at an xz level, with its SBOM and
# checksums.
package() { # directory name xz-level
    local directory=$1 name=$2 level=$3
    local archive="$repo_root/dist/$name.tar.xz"
    local sbom="$repo_root/dist/$name.spdx.json"
    tar --sort=name \
        --mtime="@${SOURCE_DATE_EPOCH:-0}" \
        --owner=0 --group=0 --numeric-owner \
        --create --use-compress-program="xz $level -T1" --file "$archive" \
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
package "$arch" "statics-$arch" -6
# The extra archive exists only for an architecture that builds an extra tool.
rm -f "$repo_root/dist/statics-extra-$arch".*
if [[ -d $repo_root/dist/$arch-extra ]]; then
    # xz -9's 64 MiB window spans all the Go tools, which share most of
    # their runtime and modules, and stunnel's and openvpn's OpenSSL:
    # about 30% smaller than -6 for the extra archive, at 65 MiB of memory
    # to decompress.
    package "$arch-extra" "statics-extra-$arch" -9
fi
