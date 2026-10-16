#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

[[ -s $repo_root/LICENSE ]] || {
    echo "missing repository license" >&2
    exit 1
}
head -n 1 "$repo_root/LICENSE" | grep -qx 'MIT License' || {
    echo "repository license is not MIT" >&2
    exit 1
}

awk -F '|' '
    /^#/ || NF == 0 { next }
    NF != 4 { print FNR ": malformed source lock record"; bad=1; next }
    seen[$1]++ { print FNR ": duplicate source " $1; bad=1 }
    # No {64} interval: mawk, the awk on Ubuntu and CircleCI images, lacks it.
    length($3) != 64 || $3 ~ /[^0-9a-f]/ {
        print FNR ": invalid SHA-256 for " $1; bad=1
    }
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

# Every hand-written CI matrix must list exactly the architectures in
# architectures.tsv. A block is an `arch:` key followed by `- name` items.
tsv_arches=$(awk -F '|' '$0 !~ /^#/ && NF { print $1 }' \
    "$repo_root/architectures.tsv" | sort)
for ci_file in "$repo_root/.github/workflows/build.yml" \
    "$repo_root/.circleci/config.yml"; do
    [[ -f $ci_file ]] || continue
    if grep -En '^[[:space:]]*arch:[[:space:]]*\[' "$ci_file"; then
        echo "${ci_file#"$repo_root"/}: write architecture matrices as block lists" >&2
        exit 1
    fi
    blocks=$(awk '
        /^[[:space:]]*arch:[[:space:]]*$/ { block++; collecting=1; indent=-1; next }
        collecting && /^[[:space:]]*-[[:space:]]+[^[:space:]]+[[:space:]]*$/ {
            match($0, /^[[:space:]]*/)
            if (indent < 0) indent = RLENGTH
            if (RLENGTH == indent) {
                sub(/^[[:space:]]*-[[:space:]]+/, ""); sub(/[[:space:]]+$/, "")
                print block "|" $0; next
            }
        }
        { collecting=0 }
    ' "$ci_file")
    [[ -n $blocks ]] || {
        echo "${ci_file#"$repo_root"/}: no architecture matrix found" >&2
        exit 1
    }
    while read -r block; do
        listed=$(awk -F '|' -v b="$block" '$1 == b { print $2 }' <<<"$blocks" | sort)
        [[ $listed == "$tsv_arches" ]] || {
            echo "${ci_file#"$repo_root"/}: architecture matrix $block disagrees with architectures.tsv:" >&2
            comm -3 <(printf '%s\n' "$tsv_arches") <(printf '%s\n' "$listed") >&2
            exit 1
        }
    done < <(cut -d '|' -f 1 <<<"$blocks" | sort -u)
done

bash -n \
    "$repo_root"/scripts/*.sh \
    "$repo_root"/scripts/builders/*.sh \
    "$repo_root"/scripts/lib/*.sh \
    "$repo_root"/scripts/toolchain/*
python3 -m py_compile "$repo_root/scripts/update_sources.py"
python3 -m py_compile "$repo_root/scripts/generate-sbom.py"
python3 "$repo_root/scripts/check-docs.py"

if grep -REn \
    '^[[:space:]]*uses:[[:space:]]+[^[:space:]#]+@(v?[0-9]+|main|master)([[:space:]#]|$)' \
    "$repo_root/.github/workflows"; then
    echo "GitHub Actions must be pinned to full commit SHAs" >&2
    exit 1
fi

# Every CircleCI image needs a digest, except machine images such as
# ubuntu-2404:current, which cannot be pinned that way.
if [[ -d $repo_root/.circleci ]] && grep -REn '^[[:space:]-]*image:' "$repo_root/.circleci" |
    grep -Ev 'image:[[:space:]]+ubuntu-[0-9]{4}:|@sha256:[0-9a-f]{64}'; then
    echo "CircleCI images must be pinned by SHA-256 digest" >&2
    exit 1
fi

grep -Eq '^FROM [^[:space:]]+@sha256:[0-9a-f]{64} AS base$' \
    "$repo_root/docker/Dockerfile" || {
    echo "the base image must be pinned by SHA-256 digest" >&2
    exit 1
}

echo "repository manifests and scripts are valid"
