#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

awk -F '|' '
    /^#/ || NF == 0 { next }
    NF != 4 { print FNR ": malformed source lock record"; bad=1; next }
    seen[$1]++ { print FNR ": duplicate source " $1; bad=1 }
    $3 !~ /^[0-9a-f]{64}$/ { print FNR ": invalid SHA-256 for " $1; bad=1 }
    $4 !~ /^https:\/\// && $1 != "socat" {
        print FNR ": non-HTTPS source " $1; bad=1
    }
    END { exit bad }
' "$repo_root/sources.lock"

awk -F '|' '
    /^#/ || NF == 0 { next }
    NF != 5 { print FNR ": malformed architecture record"; bad=1; next }
    seen[$1]++ { print FNR ": duplicate architecture " $1; bad=1 }
    END { exit bad }
' "$repo_root/architectures.tsv"

awk -F '|' '
    /^#/ || NF == 0 { next }
    NF != 3 { print FNR ": malformed component record"; bad=1; next }
    seen[$1]++ { print FNR ": duplicate component " $1; bad=1 }
    END { exit bad }
' "$repo_root/components.tsv"

comm -3 \
    <(awk -F '|' '$0 !~ /^#/ && $1 !~ /^zig-/ { print $1 }' \
        "$repo_root/sources.lock" | sort) \
    <(awk -F '|' '$0 !~ /^#/ { print $1 }' \
        "$repo_root/components.tsv" | sort) |
    grep -q . && {
        echo "sources.lock and components.tsv disagree" >&2
        exit 1
    }

bash -n \
    "$repo_root"/scripts/*.sh \
    "$repo_root"/scripts/builders/*.sh \
    "$repo_root"/scripts/lib/*.sh \
    "$repo_root"/scripts/toolchain/*
python3 -m py_compile "$repo_root/scripts/update_sources.py"
python3 -m py_compile "$repo_root/scripts/generate-sbom.py"

if grep -REn \
    '^[[:space:]]*uses:[[:space:]]+[^[:space:]#]+@(v?[0-9]+|main|master)([[:space:]#]|$)' \
    "$repo_root/.github/workflows"; then
    echo "GitHub Actions must be pinned to full commit SHAs" >&2
    exit 1
fi

grep -Eq '^FROM [^[:space:]]+@sha256:[0-9a-f]{64} AS toolchain$' \
    "$repo_root/docker/Dockerfile" || {
    echo "the toolchain base image must be pinned by SHA-256 digest" >&2
    exit 1
}

echo "repository manifests and scripts are valid"
