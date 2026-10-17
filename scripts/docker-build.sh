#!/usr/bin/env bash
# Build one Dockerfile target, using the published toolchain image as a
# layer cache.
#
# The Dockerfile stays the only definition of the toolchain: the image is a
# cache, never a FROM. BuildKit reuses its layers only when they match what
# the Dockerfile would build, and apt is pinned to the base image's Debian
# snapshot, so a hit is bit-identical to building the stage here. A missing or
# unreachable image only costs time.
#
# Usage: docker-build.sh TARGET [BUILDX_ARG...]
# TOOLCHAIN_IMAGE overrides the cache reference; set it empty to skip it.
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 TARGET [BUILDX_ARG...]" >&2
    exit 2
fi

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
target=$1
shift

cache=()
image=${TOOLCHAIN_IMAGE-ghcr.io/0typos/statics-toolchain:main}
if [[ -n $image ]]; then
    cache=(--cache-from "type=registry,ref=$image")
fi

exec docker buildx build \
    --progress=plain \
    --file "$repo_root/docker/Dockerfile" \
    --target "$target" \
    "${cache[@]}" \
    "$@" \
    "$repo_root"
