#!/usr/bin/env bash
# Print the components.tsv records that belong in one archive of one
# architecture: rows for that archive, minus Go tools on an architecture
# without Go; libraries marked `both` (linked into tools in each archive)
# wherever the archive has a tool; and Go itself (`runtime`) wherever a Go
# tool remains. Rows keep their components.tsv order.
#
# Usage: components.sh ARCH main|extra
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [[ $# -ne 2 || ! $2 =~ ^(main|extra)$ ]]; then
    echo "usage: $0 ARCH main|extra" >&2
    exit 2
fi

go_env=$(awk -F '|' -v wanted="$1" '
    $0 !~ /^#/ && $1 == wanted { print $6; found++ }
    END { if (found != 1) exit 1 }
' "$repo_root/architectures.tsv") || {
    echo "unknown or duplicated architecture: $1" >&2
    exit 2
}

awk -F '|' -v archive="$2" -v has_go="$([[ $go_env == none ]] || echo 1)" '
    /^#/ || NF == 0 { next }
    $5 == "runtime" { row[++n] = $0; kind[n] = "runtime"; next }
    $4 == "both" { row[++n] = $0; kind[n] = "both"; next }
    $4 != archive || ($5 != "-" && !has_go) { next }
    { row[++n] = $0; kind[n] = "tool"; tools++; if ($5 != "-") go_tools++ }
    END {
        for (i = 1; i <= n; i++)
            if (kind[i] == "tool" || (kind[i] == "both" && tools) ||
                (kind[i] == "runtime" && go_tools))
                print row[i]
    }
' "$repo_root/components.tsv"
