#!/usr/bin/env bash
# Sign and publish a release whose every gate has passed.
#
# Each archive gets two Sigstore bundles from a keyless cosign signature
# bound to this CircleCI project's OIDC identity: SLSA provenance
# (<archive>.provenance.sigstore.json) and, for the binary archives, the SPDX
# SBOM (<archive>.sbom.sigstore.json). Every bundle is verified against the
# expected identity before anything is published. Then the annotated tag is
# created when the candidate asks for one, the GitHub Release is created or
# its assets replaced. A monthly release then prunes releases beyond
# RELEASE_KEEP, removing each release and its assets; tags are never deleted.
#
# Usage: publish-release.sh WORKSPACE
# WORKSPACE holds the statics-* assets and release/{ref,tag,create_tag}.
# Needs GH_TOKEN, GH_REPO, SIGSTORE_ID_TOKEN, SIGSTORE_ISSUER,
# SIGSTORE_IDENTITY, RELEASE_KEEP, and CIRCLE_BUILD_URL.
set -euo pipefail

workspace=$1
release_sha=$(cat "$workspace/release/ref")
release_tag=$(cat "$workspace/release/tag")
create_tag=$(cat "$workspace/release/create_tag")
marker="Automated release built by CircleCI"

assets=$(mktemp -d)
cp "$workspace"/statics-* "$assets/"
cd "$assets"
for checksum_file in *.sha256; do
    sha256sum --check "$checksum_file"
done

jq --null-input \
    --arg repo "https://github.com/$GH_REPO" \
    --arg tag "$release_tag" \
    --arg sha "$release_sha" \
    --arg builder "$SIGSTORE_IDENTITY" \
    --arg run "$CIRCLE_BUILD_URL" \
    '{
      buildDefinition: {
        buildType: ($repo + "/blob/" + $sha + "/.circleci/config.yml"),
        externalParameters: {repository: $repo, ref: ("refs/tags/" + $tag)},
        resolvedDependencies: [{
          uri: ("git+" + $repo + "@refs/tags/" + $tag),
          digest: {gitCommit: $sha}
        }]
      },
      runDetails: {
        builder: {id: $builder},
        metadata: {invocationId: $run}
      }
    }' >"$workspace/provenance.json"

attest() { # archive type predicate bundle
    cosign attest-blob --yes \
        --identity-token "$SIGSTORE_ID_TOKEN" \
        --type "$2" --predicate "$3" --bundle "$4" "$1"
    cosign verify-blob-attestation \
        --certificate-oidc-issuer "$SIGSTORE_ISSUER" \
        --certificate-identity "$SIGSTORE_IDENTITY" \
        --type "$2" --bundle "$4" "$1"
}

for archive in statics-*.tar.xz; do
    attest "$archive" slsaprovenance1 "$workspace/provenance.json" \
        "$archive.provenance.sigstore.json"
    sbom=${archive%.tar.xz}.spdx.json
    if [[ -f $sbom ]]; then
        attest "$archive" spdxjson "$sbom" "$archive.sbom.sigstore.json"
    fi
done

if [[ $create_tag == true ]]; then
    if existing=$(gh api "repos/$GH_REPO/git/ref/tags/$release_tag" \
        --jq '.object.type + " " + .object.sha' 2>/dev/null); then
        # Another run took the name first. Publishing onto it would attach
        # these assets to a different commit than their provenance names.
        peeled=${existing#* }
        if [[ ${existing%% *} == tag ]]; then
            peeled=$(gh api "repos/$GH_REPO/git/tags/$peeled" --jq '.object.sha')
        fi
        if [[ $peeled != "$release_sha" ]]; then
            echo "tag $release_tag already points at $peeled, not $release_sha" >&2
            exit 1
        fi
        echo "tag $release_tag already exists on $release_sha; leaving it untouched"
    else
        # The CI token cannot sign, so record an annotated tag and the reason a
        # signature is unavailable, per the release policy. The marker line
        # stops the tag's own pipeline from building it a second time.
        tag_object=$(gh api "repos/$GH_REPO/git/tags" \
            --method POST \
            --raw-field tag="$release_tag" \
            --raw-field object="$release_sha" \
            --raw-field type=commit \
            --raw-field message="$release_tag

$marker: $CIRCLE_BUILD_URL
Unsigned: the CI token has no release signing key." \
            --jq '.sha')
        gh api "repos/$GH_REPO/git/refs" \
            --method POST \
            --raw-field ref="refs/tags/$release_tag" \
            --raw-field sha="$tag_object" >/dev/null
    fi
fi

if gh release view "$release_tag" >/dev/null 2>&1; then
    gh release upload "$release_tag" ./* --clobber
else
    publish=(gh release create "$release_tag" ./*
        --verify-tag
        --generate-notes
        --title "$release_tag")
    if [[ $create_tag == true ]]; then
        publish+=(--notes "Automated release from commit \`$release_sha\`.
Every architecture was built and verified under QEMU, and x86-64 was
independently rebuilt and compared, before publication. Verify the
SHA-256 files and Sigstore bundles before deploying, and see
\`docs/RELEASING.md\` for what this automation does not review.")
    fi
    "${publish[@]}"
fi

[[ $create_tag == true ]] || exit 0
if ((RELEASE_KEEP < 1)); then
    echo "RELEASE_KEEP must be at least 1" >&2
    exit 1
fi
# Drafts are somebody's work in progress and are never touched.
mapfile -t releases < <(
    gh api --paginate "repos/$GH_REPO/releases" \
        --jq '.[] | select(.draft | not) | [.published_at, .tag_name] | @tsv' |
        sed '/^$/d' |
        sort --reverse
)
for entry in "${releases[@]:RELEASE_KEEP}"; do
    tag=${entry#*$'\t'}
    # No --cleanup-tag: the tag stays, so the release remains reproducible
    # from source after its binaries are removed.
    gh release delete "$tag" --yes
    echo "pruned $tag (assets removed, tag kept)"
done
