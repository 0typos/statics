#!/usr/bin/env bash
# Run a build command, and run it once more only if it failed fast.
#
# The window itself is retry-window.sh's decision, so this wrapper and the
# GitHub workflow can never disagree about what counts as a transient failure.
# OUTPUT_DIR is removed before the retry so later steps only ever see the
# output of a run that completed.
#
# Usage: retry-once.sh OUTPUT_DIR COMMAND [ARG...]
set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "usage: $0 OUTPUT_DIR COMMAND [ARG...]" >&2
    exit 2
fi

output_dir=$1
shift

started=$(date +%s)
if "$@"; then
    exit 0
fi

verdict=$(mktemp)
trap 'rm -f "$verdict"' EXIT
GITHUB_OUTPUT=$verdict "$(dirname "${BASH_SOURCE[0]}")/retry-window.sh" "$started"
grep -qx 'retry=true' "$verdict" || exit 1

rm -rf "$output_dir"
"$@"
