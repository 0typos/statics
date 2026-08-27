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

source "$repo_root/scripts/lib/build-common.sh"
# shellcheck disable=SC1090  # builder file is chosen by the DAG at run time
source "$repo_root/scripts/builders/$1.sh"
"$2"
