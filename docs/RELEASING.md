# Release process

Releases are published two ways: a maintainer pushes a `v*` tag, or the
monthly schedule builds and tags on its own. Both run CircleCI's `release`
workflow (`.circleci/config.yml`) with identical gates, and neither can
publish unless every one passes.
Project policy requires a signed tag when available, or an annotated tag with
the reason a signature was unavailable. A GitHub Release is published only
after:

1. repository validation and ShellCheck pass;
2. every architecture builds and passes static/QEMU verification;
3. the x86-64 archive being released is byte-identical to an independent
   rebuild without any cache, toolchain included;
4. the corresponding-source archive is packaged;
5. every archive is signed keylessly through CircleCI's OIDC identity, and
   each signature verifies against that identity;
6. every downloaded release asset passes its portable SHA-256 file.

The release contains, for every architecture:

- `statics-<arch>.tar.xz` and its SHA-256 file;
- a standalone deterministic SPDX 2.3 SBOM and its SHA-256 file;
- Sigstore bundles `statics-<arch>.tar.xz.provenance.sigstore.json` (SLSA
  provenance) and `statics-<arch>.tar.xz.sbom.sigstore.json` (the SBOM).

It also contains `statics-sources.tar.xz`, its SHA-256 file, and its
provenance bundle. Binary
archives include `BUILDINFO`, `COMPONENTS.tsv`, `sources.lock`,
`THIRD_PARTY_NOTICES.md`, `BUILD_RECIPES_LICENSE`, the SPDX SBOM, and all
relevant upstream license texts. The build-recipe license is MIT; every
upstream component remains under its separately recorded terms.

## Preflight

Release from a reviewed commit on `main`, with no uncommitted release changes:

```console
git status --short
./scripts/validate.sh
shellcheck scripts/*.sh scripts/builders/*.sh scripts/lib/*.sh scripts/toolchain/*
make smoke ARCH=x86_64
make package ARCH=x86_64
```

The branch protection and latest CircleCI `ci-ok` on `main` must be green for
the full matrix. The local x86-64 package is a fast preflight, not a substitute for
that matrix, the reproducibility job, or the corresponding-source
job.

Review:

- the diff since the previous tag;
- all `sources.lock` changes and upstream release notes/signatures;
- `components.tsv`, packaged notices, and license changes;
- documented feature/architecture limitations;
- the CircleCI image and tool pins, and the base-image digest.

Never tag an unreviewed automated source-update branch by hand. Publishing
unreviewed pins is only acceptable through the monthly release below, whose
gates and trade-offs are documented and whose output is labelled as automated.

## Creating a release

Use a sortable project version. The established date-based form is:

```console
git tag -s vYYYY.MM.DD -m "vYYYY.MM.DD"
git push origin vYYYY.MM.DD
```

If signed tags are unavailable, create an annotated tag and record why in the
release process. Do not use a lightweight tag.

```console
git tag -a vYYYY.MM.DD -m "vYYYY.MM.DD"
git push origin vYYYY.MM.DD
```

The tag's pipeline builds, verifies, signs, and publishes it. Signing uses
cosign with no stored key: Fulcio certifies the job as this project's
CircleCI pipeline definition, and every signature is logged in Rekor. The
standalone SPDX file is checksum-linked to the release assets; the SBOM
bundle's subject is the binary archive. See
[Verify published assets](#verify-published-assets).

## Automated monthly release

A CircleCI schedule runs the `release` workflow with `task=monthly-release`
at 03:19 UTC on the first day of each month. Start one by hand with:

```console
circleci pipeline run --project PROJECT --definition-id DEFINITION \
  --branch main --param task=monthly-release
```

It:

1. repins every component in `sources.lock` to its latest upstream release;
2. digests every path that can change an artifact, compares it against the
   same digest for the last release, and stops without building when they
   match. `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, and `docs/` are
   excluded because no build copies them; `LICENSE`, the manifests, the
   scripts, the Docker context, and the CI config all count, and any path
   added later counts unless it is added to that exclusion list. A tag that
   cannot be read is treated as changed, so the run builds rather than
   assumes;
3. commits the refreshed pins to `automation/monthly-release` when they
   changed, so the tag, the signatures, and the packaged `sources.lock` all
   describe one real commit (`scripts/release-candidate.sh`);
4. builds that commit through the same jobs as a tag, so validation, the full
   architecture matrix, QEMU verification, the uncached reproducibility
   comparison, the source bundle, and the signatures all apply unchanged;
5. creates annotated tag `vYYYY.MM.DD` on the built commit and publishes the
   release only after every gate reports success;
6. prunes published releases beyond the most recent `RELEASE_KEEP` (24, or
   two years of monthly releases; maintainer tag releases never prune). Only
   the release and its assets are
   removed. **Tags are never deleted**, so a pruned version stays buildable
   from source and its commit stays reachable; `gh release delete` is called
   without `--cleanup-tag`. Draft releases are ignored, and pruning runs only
   after a release has actually been published.

Nothing is tagged before the build succeeds. The tag's own pipeline sees the
automation marker in the tag message and builds nothing. A failed month
leaves the candidate on `automation/monthly-release`, publishes nothing, and
shows as a failed CircleCI pipeline; the next run resets the branch and
retries. When the
date is already taken the tag becomes `vYYYY.MM.DD.1`, `.2`, and so on.

This path trades maintainer review of upstream releases for unattended
delivery. It repins and publishes without a human reading upstream release
notes or checking upstream signatures, which the reviewed
`update-sources` pull request into `main` (weekly schedule,
`task=update-sources`, `scripts/update-sources-pr.sh`) still exists to do. Two
supported ways to keep review in the loop:

- release only what `main` already pins, by setting the schedule's
  `refresh_sources` parameter to `false`. The monthly run then rebuilds and
  publishes reviewed pins, and merged update PRs are what make a release
  contain anything new;
- delete the schedule and start the monthly release by hand, which keeps the
  one-command build-and-publish path without the calendar.

A monthly run takes two parameters: `refresh_sources` (repin, default true)
and `force` (release even when nothing changed, default false).

## Verify published assets

```console
mkdir statics-release
cd statics-release
gh release download vYYYY.MM.DD --repo OWNER/REPOSITORY
sha256sum --check statics-x86_64.tar.xz.sha256
sha256sum --check statics-x86_64.spdx.json.sha256
sha256sum --check statics-sources.tar.xz.sha256
cosign verify-blob-attestation statics-x86_64.tar.xz \
  --bundle statics-x86_64.tar.xz.provenance.sigstore.json \
  --type slsaprovenance1 \
  --certificate-oidc-issuer https://oidc.circleci.com/org/c0406229-6c92-431c-9d62-ee307025beeb \
  --certificate-identity https://circleci.com/api/v2/projects/ff2a4ca6-e625-4190-be64-b5fcee9a68cb/pipeline-definitions/de8b6d78-390e-4809-a387-a80e241419b3
tar -tJf statics-x86_64.tar.xz
```

Use `--type spdxjson` with the `.sbom.sigstore.json` bundle to verify the
SBOM. The issuer is this project's CircleCI organization and the identity its
pipeline definition. That proves a job of this CircleCI project signed the
archive with the publishing context, which only `main`, admin-created `v*`
tags, and the schedules can use; the provenance inside names the tag and
commit. Releases published before the October 2026 move to CircleCI were
built on GitHub Actions and verify with `gh attestation verify ARCHIVE --repo 0typos/statics` instead.

Verify the architecture actually being deployed, not only x86-64. Inspect
`BUILDINFO`, `sources.lock`, `BUILD_RECIPES_LICENSE`,
`THIRD_PARTY_NOTICES.md`, and `SBOM.spdx.json` inside the extracted target
directory.

Re-running a maintainer tag's pipeline verifies the build again and replaces
assets on the existing GitHub Release. It does not bypass any build or
reproducibility gate. A monthly tag's own pipeline builds nothing; to retry a
monthly release, re-run the failed jobs of the monthly pipeline itself.

## Repository settings

The default branch must require CircleCI's `ci-ok` check before accepting
changes; it passes only when validation, every architecture, and the source
bundle pass. Keep force pushes
and branch deletion disabled.

Before the first public push, create the repository without initializing it,
set `main` as the default branch, and push only the reviewed `main` history.
Confirm that the repository owner and URL in local Git configuration are the
intended public destination before setting `origin`.

The CircleCI pipeline definition needs an all-pushes trigger, a tags-only
trigger, and three schedules (weekly `task=reproducibility`, monthly
`task=monthly-release`, weekly `task=update-sources`, all on `main`).

The `statics-toolchain` GHCR package must stay public, so every job can
pull it anonymously. A missing image only costs time: builds rebuild the
toolchain stage themselves.

Release maintainers should also enable GitHub private vulnerability reporting
when available. Enable Dependabot alerts and security updates, and protect the
`v*` tag namespace so only release maintainers can create or update release
tags. See the [security policy](../SECURITY.md) for the reporting and trust
model.

Publishing uses the CircleCI context `statics-publish`, restricted to this
project and to pipelines on `main` or a `v*` tag:

- `GITHUB_REPO_TOKEN`: a fine-grained token for `0typos/statics` only, with
  Contents and Pull requests read/write. It tags, publishes and prunes
  releases, writes the two automation branches, and opens the update PR.
  Because it is not GitHub's workflow token, its pushes start CircleCI
  pipelines like any other push.
- `GHCR_TOKEN`: a classic token with only `write:packages`, for the
  toolchain image.

Rotate both before they expire. Signing needs no secret: the job's OIDC token
is minted per run. The context is also withheld from SSH reruns.

A `v*` tag pipeline runs the configuration at the tagged commit with both
tokens and the signing identity, so whoever can create a `v*` tag can
publish and sign anything. Two rulesets hold this together:

- `Protect release tags` blocks deletion and non-fast-forward updates of
  `v*` tags, with no bypass;
- `Restrict release tag creation` lets only the Repository admin role create
  `v*` tags. The monthly run tags as the token's account, which must stay an
  admin, or it builds everything and then fails at the tag step.

Keep these two separate: a bypass applies to every rule in its ruleset.
`automation/monthly-release` must also be creatable and force-updatable, so
scope branch protection to `main` rather than all branches.

Nothing here lets the automation write to `main`. The candidate commit lives
on its own branch, and the reviewed source-update PR remains the only way
refreshed pins reach the default branch.
