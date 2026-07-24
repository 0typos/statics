#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [[ $# -ne 1 ]]; then
    echo "usage: $0 ARCH" >&2
    exit 2
fi

arch=$1
input="$repo_root/dist/$arch"
archive="$repo_root/dist/statics-$arch.tar.xz"

[[ -d $input ]] || {
    echo "build output not found: $input" >&2
    exit 1
}

tar --sort=name \
    --mtime="@${SOURCE_DATE_EPOCH:-0}" \
    --owner=0 --group=0 --numeric-owner \
    --create --xz --file "$archive" \
    --directory "$repo_root/dist" "$arch"
sha256sum "$archive" > "$archive.sha256"
echo "$archive"
