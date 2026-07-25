#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
input=${1:-"$repo_root/dist/sources"}
archive=${2:-"$repo_root/dist/statics-sources.tar.xz"}

[[ -d $input ]] || {
    echo "source bundle not found: $input" >&2
    exit 1
}

mkdir -p "$(dirname "$archive")"
tar --sort=name \
    --mtime="@${SOURCE_DATE_EPOCH:-0}" \
    --owner=0 --group=0 --numeric-owner \
    --create --xz --file "$archive" \
    --directory "$(dirname "$input")" "$(basename "$input")"
(
    cd "$(dirname "$archive")"
    sha256sum "$(basename "$archive")" > "$(basename "$archive").sha256"
)
echo "$archive"
