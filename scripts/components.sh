#!/usr/bin/env bash
# Print the components.tsv records that belong in one archive of one
# architecture: rows for that archive, minus Go tools on an architecture
# without Go, and tcc and its musl on one tcc has no code generator for;
# libraries marked `both` (linked into tools in each archive)
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

record=$(awk -F '|' -v wanted="$1" '
    $0 !~ /^#/ && $1 == wanted { print $6 "|" $7; found++ }
    END { if (found != 1) exit 1 }
' "$repo_root/architectures.tsv") || {
    echo "unknown or duplicated architecture: $1" >&2
    exit 2
}
IFS='|' read -r go_env tcc_cpu <<<"$record"

awk -F '|' -v archive="$2" -v has_go="$([[ $go_env == none ]] || echo 1)" \
    -v has_tcc="$([[ $tcc_cpu == none ]] || echo 1)" '
    /^#/ || NF == 0 { next }
    ($1 == "tcc" || $1 == "musl") && !has_tcc { next }
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
