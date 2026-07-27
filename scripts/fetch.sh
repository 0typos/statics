#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
lock_file=${SOURCES_LOCK:-"$repo_root/sources.lock"}

if [[ $# -ne 2 ]]; then
    echo "usage: $0 NAME OUTPUT" >&2
    exit 2
fi

name=$1
output=$2

if [[ ! $name =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo "invalid source name: $name" >&2
    exit 2
fi

record=$(awk -F '|' -v wanted="$name" '
    $0 !~ /^#/ && $1 == wanted {
        if (found++) exit 3
        print
    }
    END {
        if (!found) exit 2
    }
' "$lock_file") || {
    echo "source '$name' is missing or duplicated in $lock_file" >&2
    exit 2
}

IFS='|' read -r _ version expected_sha url <<<"$record"
mkdir -p "$(dirname "$output")"

if [[ -f $output ]] && printf '%s  %s\n' "$expected_sha" "$output" | sha256sum --check --status; then
    echo "using cached $name $version"
    exit 0
fi

temporary=$(mktemp "${output}.partial.XXXXXX")
trap 'rm -f "$temporary"' EXIT

echo "fetching $name $version"
# Retrying a download is always safe: the result is rejected below unless it
# matches the pinned digest, so a retry can only recover a transport failure.
curl --fail --location --proto '=http,https' --show-error --silent \
    --retry 5 --retry-connrefused --retry-max-time 600 --connect-timeout 30 \
    --user-agent 'statics-source-fetcher/1.0' "$url" --output "$temporary"
printf '%s  %s\n' "$expected_sha" "$temporary" | sha256sum --check --status || {
    echo "checksum mismatch for $name $version" >&2
    exit 1
}

mv "$temporary" "$output"
trap - EXIT
