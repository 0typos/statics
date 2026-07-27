#!/usr/bin/env bash
# Decide whether a set of paths can change a built artifact.
#
# This is the single definition of "documentation only" for the repository. It
# is deliberately an allow-nothing list rather than an allow-list: a path counts
# as a build input unless it is named here, so anything added later is treated
# as load-bearing until someone decides otherwise.
#
# LICENSE is NOT in this list. It ships in every archive as
# BUILD_RECIPES_LICENSE and is recorded in the SBOM, so editing it changes the
# artifacts.
#
# Usage:
#   build-relevant.sh --any      < paths   exit 0 if any path is a build input
#   build-relevant.sh --filter   < lines   print lines whose path is a build input
#
# --filter treats the last whitespace-separated field of each line as the path,
# so it accepts both bare paths and "<object> <path>" pairs.
set -euo pipefail

NON_BUILD_PATHS=(
    'README.md'
    'CONTRIBUTING.md'
    'SECURITY.md'
    'docs/'
)

pattern="^($(
    IFS='|'
    printf '%s' "${NON_BUILD_PATHS[*]}"
))"
# Escape the dots so "READMExmd" cannot masquerade as documentation.
pattern=${pattern//./\\.}

mode=${1:-}
case $mode in
--any)
    while read -r line; do
        [[ -n $line ]] || continue
        path=${line##* }
        [[ $path =~ $pattern ]] || exit 0
    done
    exit 1
    ;;
--filter)
    while IFS= read -r line; do
        [[ -n $line ]] || continue
        path=${line##* }
        [[ $path =~ $pattern ]] || printf '%s\n' "$line"
    done
    ;;
*)
    echo "usage: $0 --any|--filter" >&2
    exit 2
    ;;
esac
