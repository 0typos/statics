#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
archive_dir=${SOURCE_ARCHIVE_DIR:-"$repo_root/.build/source-archives"}
extract_dir=
bundle_dir=

while (($#)); do
    case "$1" in
        --archives)
            archive_dir=$2
            shift 2
            ;;
        --extract)
            extract_dir=$2
            shift 2
            ;;
        --bundle)
            bundle_dir=$2
            shift 2
            ;;
        *)
            echo "usage: $0 [--archives DIR] [--extract DIR] [--bundle DIR]" >&2
            exit 2
            ;;
    esac
done

mkdir -p "$archive_dir"
[[ -z $extract_dir ]] || mkdir -p "$extract_dir"
[[ -z $bundle_dir ]] || mkdir -p "$bundle_dir"

while IFS='|' read -r name _version _ url; do
    [[ $name == \#* || -z $name ]] && continue
    [[ $name == zig-* ]] && continue

    filename=${url##*/}
    archive="$archive_dir/$filename"
    "$repo_root/scripts/fetch.sh" "$name" "$archive"

    if [[ -n $bundle_dir ]]; then
        cp "$archive" "$bundle_dir/$filename"
    fi

    if [[ -n $extract_dir ]]; then
        destination="$extract_dir/$name"
        if [[ -e $destination ]]; then
            echo "refusing to replace existing source directory: $destination" >&2
            exit 1
        fi
        mkdir -p "$destination"
        tar --extract --file "$archive" --directory "$destination" --strip-components=1
    fi
done < "$repo_root/sources.lock"

cp "$repo_root/sources.lock" "$archive_dir/sources.lock"
[[ -z $bundle_dir ]] || cp "$repo_root/sources.lock" "$bundle_dir/sources.lock"
