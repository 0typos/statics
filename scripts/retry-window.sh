#!/usr/bin/env bash
# Decide whether a failed build is worth exactly one retry.
#
# Infrastructure failures — registry timeouts, DNS, package-mirror hiccups —
# surface in the first minutes, before any component is compiled. A genuine
# build break takes far longer to reach. Retrying only inside that window
# recovers the transient class without ever spending a second full build on a
# real breakage.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 STARTED_EPOCH_SECONDS" >&2
    exit 2
fi

started=$1
window=${RETRY_WINDOW_SECONDS:-600}

[[ $started =~ ^[0-9]+$ ]] || {
    echo "invalid start time: $started" >&2
    exit 2
}
[[ $window =~ ^[0-9]+$ ]] || {
    echo "invalid retry window: $window" >&2
    exit 2
}

elapsed=$(($(date +%s) - started))

if ((elapsed <= window)); then
    verdict=true
    echo "failed after ${elapsed}s, inside the ${window}s window: retrying once"
else
    verdict=false
    echo "failed after ${elapsed}s, past the ${window}s window: real failure"
fi

if [[ -n ${GITHUB_OUTPUT:-} ]]; then
    echo "retry=$verdict" >>"$GITHUB_OUTPUT"
fi
