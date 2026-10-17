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

# A component still running after STATICS_COMPONENT_TIMEOUT seconds is
# treated as hung: it is killed and marked, and build.sh restarts the whole
# architecture once from a clean tree. Builders patch and link in place, so
# re-running one component on its own partial tree is not safe. CircleCI
# hosts have intermittently livelocked one process at 100% of a core (nmap's
# final mips link, 2 of 6 runs) where the step normally takes under a second.
limit=${STATICS_COMPONENT_TIMEOUT:-}
if [[ -n $limit && -z ${STATICS_UNDER_TIMEOUT:-} ]]; then
    started=$SECONDS
    rc=0
    # KILL, not TERM: the tree is discarded, and a grandchild that ignored
    # TERM would otherwise outlive its shell and keep writing into it.
    STATICS_UNDER_TIMEOUT=1 timeout --signal=KILL "${limit}s" "$0" "$@" || rc=$?
    # Only a run that reached the limit counts; an OOM kill also exits 137.
    if ((rc == 124 || rc == 137)) && ((SECONDS - started >= limit)); then
        echo "==> $1/$2 still running after ${limit}s; treating it as hung" >&2
        touch "$WORK_DIR/.hung"
    fi
    exit "$rc"
fi

source "$repo_root/scripts/lib/build-common.sh"
# shellcheck disable=SC1090  # builder file is chosen by the DAG at run time
source "$repo_root/scripts/builders/$1.sh"
"$2"
