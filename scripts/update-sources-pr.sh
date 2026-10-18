#!/usr/bin/env bash
# Repin upstream sources and propose the result as a pull request into main.
#
# The commit goes to UPDATE_BRANCH through the API, so CI needs no Git push
# credential. That push starts the branch's own CircleCI pipeline, whose
# ci-ok status the pull request then waits on. An unchanged pin set, or one
# the open branch already carries, leaves the branch and its pipeline alone.
#
# Usage: update-sources-pr.sh
# Needs GH_TOKEN, GH_REPO, and UPDATE_BRANCH.
set -euo pipefail

summary=$(mktemp)
GITHUB_TOKEN=$GH_TOKEN ./scripts/update_sources.py --write | tee "$summary"

if git diff --quiet -- sources.lock; then
    echo "every pin is current"
    exit 0
fi

lock_blob=$(git hash-object sources.lock)
if gh api "repos/$GH_REPO/git/ref/heads/$UPDATE_BRANCH" >/dev/null 2>&1; then
    branch_blob=$(gh api "repos/$GH_REPO/contents/sources.lock?ref=$UPDATE_BRANCH" \
        --jq '.sha' 2>/dev/null || true)
    if [[ $branch_blob == "$lock_blob" ]]; then
        echo "$UPDATE_BRANCH already carries these pins"
    else
        gh api "repos/$GH_REPO/git/refs/heads/$UPDATE_BRANCH" \
            --method PATCH \
            --raw-field sha="$(git rev-parse HEAD)" \
            --field force=true >/dev/null
        branch_blob=""
    fi
else
    gh api "repos/$GH_REPO/git/refs" \
        --method POST \
        --raw-field ref="refs/heads/$UPDATE_BRANCH" \
        --raw-field sha="$(git rev-parse HEAD)" >/dev/null
    branch_blob=""
fi

if [[ $branch_blob != "$lock_blob" ]]; then
    gh api "repos/$GH_REPO/contents/sources.lock" \
        --method PUT \
        --raw-field branch="$UPDATE_BRANCH" \
        --raw-field sha="$(git rev-parse HEAD:sources.lock)" \
        --raw-field content="$(base64 --wrap=0 sources.lock)" \
        --raw-field message="chore: update pinned upstream sources" >/dev/null
fi

open=$(gh pr list --head "$UPDATE_BRANCH" --state open --json number --jq 'length')
if ((open > 0)); then
    echo "pull request already open for $UPDATE_BRANCH"
    exit 0
fi
gh pr create \
    --base main \
    --head "$UPDATE_BRANCH" \
    --label dependencies \
    --title "chore: update pinned upstream sources" \
    --body "Automated upstream release check.

Source archives were downloaded and SHA-256 pins were regenerated.
CI must cross-build and QEMU-smoke-test every architecture before merge.
Maintainers should review upstream release notes and signatures.

\`\`\`
$(cat "$summary")
\`\`\`"
