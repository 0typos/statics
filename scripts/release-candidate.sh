#!/usr/bin/env bash
# Decide what a release pipeline builds, and record it for every later job.
#
# A v* tag pipeline releases its own tag, unless the monthly automation
# created that tag: its pipeline has already built, signed, and published it.
#
# A monthly pipeline repins every upstream component (unless REFRESH_SOURCES
# is false), digests every path that can change an artifact, and compares the
# digest with the latest release's. When they differ, or FORCE_RELEASE is
# true, it picks the next free vYYYY.MM.DD tag. Refreshed pins are committed
# to RELEASE_BRANCH so the build, the tag, and the packaged sources.lock all
# describe one real commit. Nothing is tagged here: publish-release.sh tags
# the candidate only after every gate has passed.
#
# Usage: release-candidate.sh OUT_DIR
# Writes OUT_DIR/release (true or false), ref, tag, create_tag, and reason.
# The monthly path needs GH_TOKEN and GH_REPO.
set -euo pipefail

out=$1
# publish-release.sh writes this line into every tag it creates.
marker="Automated release built by CircleCI"

mkdir -p "$out"
record() { printf '%s\n' "$2" >"$out/$1"; }

if [[ -n ${CIRCLE_TAG:-} ]]; then
    git fetch --quiet --force origin "+refs/tags/$CIRCLE_TAG:refs/tags/$CIRCLE_TAG"
    if [[ $(git cat-file -t "refs/tags/$CIRCLE_TAG") == tag ]] &&
        git cat-file tag "refs/tags/$CIRCLE_TAG" | grep -qF "$marker"; then
        record release false
        record reason "$CIRCLE_TAG was created and published by the monthly release"
    else
        record release true
        record ref "$(git rev-parse "refs/tags/$CIRCLE_TAG^{commit}")"
        record tag "$CIRCLE_TAG"
        record create_tag false
        record reason "tag push"
    fi
    cat "$out/reason"
    exit 0
fi

if [[ ${REFRESH_SOURCES:-true} == true ]]; then
    # update_sources.py rewrites sources.lock only after every discovery and
    # digest succeeds, so a failed run leaves the pins untouched.
    GITHUB_TOKEN=$GH_TOKEN ./scripts/update_sources.py --write
fi
./scripts/validate.sh

base_sha=$(git rev-parse HEAD)
if git diff --quiet -- sources.lock; then
    repinned=false
else
    repinned=true
fi

# Only tracked modifications are staged, so scratch files can never make an
# unchanged candidate look new.
git add --update
candidate_tree=$(git write-tree)

# scripts/build-relevant.sh is the single definition of which paths can
# change an artifact.
input_digest() {
    git ls-tree -r --full-tree --format='%(objectname) %(path)' "$1" |
        ./scripts/build-relevant.sh --filter |
        sha256sum |
        cut -d ' ' -f 1
}

candidate_digest=$(input_digest "$candidate_tree")

previous_tag=$(gh api "repos/$GH_REPO/releases/latest" --jq '.tag_name' 2>/dev/null) ||
    previous_tag=""
released_digest=""
if [[ -n $previous_tag ]] && git fetch --quiet --depth 1 --no-tags origin \
    "+refs/tags/$previous_tag:refs/tags/$previous_tag" 2>/dev/null; then
    released_digest=$(input_digest "refs/tags/$previous_tag^{tree}")
fi

release=true
if [[ -z $previous_tag ]]; then
    reason="no previous release exists"
elif [[ -z $released_digest ]]; then
    reason="$previous_tag is unreadable; building rather than assuming"
elif [[ $candidate_digest != "$released_digest" ]]; then
    reason="build inputs changed since $previous_tag"
elif [[ ${FORCE_RELEASE:-false} == true ]]; then
    reason="build inputs match $previous_tag; released on request"
else
    release=false
    reason="build inputs match $previous_tag; nothing to release"
fi

record release "$release"
record reason "$reason"
echo "$reason (upstream pins refreshed: $repinned)"
[[ $release == true ]] || exit 0

base_tag="v$(date --utc +%Y.%m.%d)"
tag="$base_tag"
attempt=1
while gh api "repos/$GH_REPO/git/ref/tags/$tag" >/dev/null 2>&1; do
    tag="$base_tag.$attempt"
    attempt=$((attempt + 1))
done

candidate_sha="$base_sha"
if [[ $repinned == true ]]; then
    if gh api "repos/$GH_REPO/git/ref/heads/$RELEASE_BRANCH" >/dev/null 2>&1; then
        gh api "repos/$GH_REPO/git/refs/heads/$RELEASE_BRANCH" \
            --method PATCH \
            --raw-field sha="$base_sha" \
            --field force=true >/dev/null
    else
        gh api "repos/$GH_REPO/git/refs" \
            --method POST \
            --raw-field ref="refs/heads/$RELEASE_BRANCH" \
            --raw-field sha="$base_sha" >/dev/null
    fi
    candidate_sha=$(gh api "repos/$GH_REPO/contents/sources.lock" \
        --method PUT \
        --raw-field branch="$RELEASE_BRANCH" \
        --raw-field sha="$(git rev-parse "$base_sha:sources.lock")" \
        --raw-field content="$(base64 --wrap=0 sources.lock)" \
        --raw-field message="chore: pin latest upstream sources for $tag" \
        --jq '.commit.sha')
fi

record ref "$candidate_sha"
record tag "$tag"
record create_tag true
echo "building and releasing $candidate_sha as $tag"
