#!/usr/bin/env bash
# Execute one component builder inside the build DAG (scripts/build.sh).
# Usage: run-builder.sh BUILDER_FILE FUNCTION
# Environment (CC, WORK_DIR, DEPS_PREFIX, JOBS, ...) comes from build.sh.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [[ $# -ne 2 ]]; then
    echo "usage: $0 BUILDER_FILE FUNCTION" >&2
    exit 2
fi

# A component that runs past STATICS_COMPONENT_TIMEOUT is treated as hung and
# run once more. CircleCI hosts have intermittently livelocked a single
# process at 100% of one core (nmap's final mips link, 2 of 6 runs) where the
# same step normally takes under a second; a genuine failure still fails.
limit=${STATICS_COMPONENT_TIMEOUT:-}
if [[ -n $limit && -z ${STATICS_UNDER_TIMEOUT:-} ]]; then
    for attempt in 1 2; do
        rc=0
        STATICS_UNDER_TIMEOUT=1 timeout --kill-after=30s "$limit" "$0" "$@" || rc=$?
        if ((rc != 124 && rc != 137)); then
            exit "$rc"
        fi
        echo "==> $1/$2 exceeded $limit on attempt $attempt (exit $rc); treating it as hung" >&2
    done
    exit 124
fi

source "$repo_root/scripts/lib/build-common.sh"
# shellcheck disable=SC1090  # builder file is chosen by the DAG at run time
source "$repo_root/scripts/builders/$1.sh"
"$2"
