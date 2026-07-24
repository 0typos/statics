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

bash -n \
    "$repo_root"/scripts/*.sh \
    "$repo_root"/scripts/builders/*.sh \
    "$repo_root"/scripts/lib/*.sh \
    "$repo_root"/scripts/toolchain/*
python3 -m py_compile "$repo_root/scripts/update_sources.py"

echo "repository manifests and scripts are valid"
