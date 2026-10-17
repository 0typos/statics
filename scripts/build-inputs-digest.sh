#!/usr/bin/env bash
# Print a digest of every tracked file that can change a compiled artifact.
#
# CI keys cached compile output on this digest plus the architecture. It is a
# denylist on purpose: a file added later counts as an input until someone
# lists it here, so drift can only cost a cache miss, never serve stale
# output. Listed paths are documentation, CI orchestration, and checks that
# run after the build; none of them is copied into the builder stage.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# Directories match by prefix, files exactly. package.sh is an input: CI
# caches its archive, and a hit must repackage to the same bytes.
NOT_INPUTS='^((docs|assets|\.github|\.circleci)/|(README\.md|CONTRIBUTING\.md|SECURITY\.md|flake\.(nix|lock)|Makefile|scripts/(verify|validate|compare-builds|package-sources|retry-once|retry-window|build-inputs-digest)\.sh|scripts/(check-docs|update_sources)\.py)$)'

cd "$repo_root"
# Mode and working-tree content of each tracked input, so the digest matches
# what a build of this checkout would copy, including uncommitted edits.
git ls-files -s |
    NOT_INPUTS=$NOT_INPUTS awk '{ path = $4; if (path !~ ENVIRON["NOT_INPUTS"]) print $1, path }' |
    LC_ALL=C sort -k 2 |
    while read -r mode path; do
        printf '%s %s %s\n' "$mode" "$(sha256sum <"$path" | cut -d ' ' -f 1)" "$path"
    done |
    sha256sum |
    cut -d ' ' -f 1
