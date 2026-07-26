# Release process

Releases are published two ways: a maintainer pushes a `v*` tag, or the
`Monthly release` workflow builds and tags on its own schedule. Both run the
identical `Build` gates, and neither can publish unless every one passes.
Project policy requires a signed tag when available, or an annotated tag with
the reason a signature was unavailable. A GitHub Release is published only
after:

1. repository validation and ShellCheck pass;
2. every architecture builds and passes static/QEMU verification;
3. two independent, uncached x86-64 builds have identical contents;
4. the corresponding-source archive is packaged;
5. public releases receive GitHub/Sigstore attestations in isolated jobs;
6. every downloaded release asset passes its portable SHA-256 file.

The release contains, for every architecture:

- `statics-<arch>.tar.xz` and its SHA-256 file;
- a standalone deterministic SPDX 2.3 SBOM and its SHA-256 file.

It also contains `statics-sources.tar.xz` and its SHA-256 file. Binary
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

The branch protection and latest `Build` workflow must be green for the full
matrix. The local x86-64 package is a fast preflight, not a substitute for
that matrix, the uncached reproducibility job, or the corresponding-source
job.

Review:

- the diff since the previous tag;
- all `sources.lock` changes and upstream release notes/signatures;
- `components.tsv`, packaged notices, and license changes;
- documented feature/architecture limitations;
- the workflow pins and base-image digest.

Never tag an unreviewed automated source-update branch by hand. Publishing
unreviewed pins is only acceptable through the monthly workflow below, whose
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

For public repositories, the workflow attaches a GitHub/Sigstore SBOM
attestation to each binary archive and a provenance attestation to the
corresponding-source archive. Verify one with:

```console
gh attestation verify statics-x86_64.tar.xz --repo OWNER/REPOSITORY
```

The standalone SPDX file is checksum-linked to the release assets. The SBOM
attestation's subject is the binary archive.

## Automated monthly release

`Monthly release` runs at 03:19 UTC on the first day of each month and can be
started by hand from the Actions tab. It:

1. repins every component in `sources.lock` to its latest upstream release;
2. compares the resulting tree against the tree the last release was built
   from, and stops without building when they are identical;
3. commits the refreshed pins to `automation/monthly-release` when they
   changed, so the tag, the attestations, and the packaged `sources.lock` all
   describe one real commit;
4. calls the same `Build` workflow with that commit, so validation, the full
   architecture matrix, QEMU verification, the uncached reproducibility
   comparison, the source bundle, and the attestations all apply unchanged;
5. creates annotated tag `vYYYY.MM.DD` on the built commit and publishes the
   release only after every gate reports success.

Nothing is tagged before the build succeeds. A failed month leaves the
candidate on `automation/monthly-release`, publishes nothing, and notifies
whoever watches Actions; the next run resets the branch and retries. When the
date is already taken the tag becomes `vYYYY.MM.DD.1`, `.2`, and so on.

This path trades maintainer review of upstream releases for unattended
delivery. It repins and publishes without a human reading upstream release
notes or checking upstream signatures, which the reviewed
[`update-sources`](../.github/workflows/update-sources.yml) pull request into
`main` still exists to do. Two supported ways to keep review in the loop:

- release only what `main` already pins, by setting `REFRESH_SOURCES` to
  `false` in [the workflow](../.github/workflows/monthly-release.yml). The
  monthly run then rebuilds and publishes reviewed pins, and merged update
  PRs are what make a release contain anything new;
- disable the schedule and dispatch `Monthly release` manually, which keeps
  the one-click build-and-publish path without the calendar.

Manual dispatch takes two inputs: `refresh_sources` (repin, default true) and
`force` (release even when nothing changed, default false).

Scheduled workflows are disabled automatically after 60 days without
repository activity. Confirm the schedule is still enabled after a quiet
period.

## Verify published assets

```console
mkdir statics-release
cd statics-release
gh release download vYYYY.MM.DD --repo OWNER/REPOSITORY
sha256sum --check statics-x86_64.tar.xz.sha256
sha256sum --check statics-x86_64.spdx.json.sha256
sha256sum --check statics-sources.tar.xz.sha256
gh attestation verify statics-x86_64.tar.xz --repo OWNER/REPOSITORY
tar -tJf statics-x86_64.tar.xz
```

Verify the architecture actually being deployed, not only x86-64. Inspect
`BUILDINFO`, `sources.lock`, `BUILD_RECIPES_LICENSE`,
`THIRD_PARTY_NOTICES.md`, and `SBOM.spdx.json` inside the extracted target
directory.

Re-running the tag workflow verifies the build again and replaces assets on
the existing GitHub Release. It does not bypass any build or reproducibility
gate.

## Repository settings

The default branch must require `Validate repository`, `Reproducibility`, and
every `Build <architecture>` check before accepting changes. Keep force pushes
and branch deletion disabled.

Before the first public push, create the repository without initializing it,
set `main` as the default branch, and push only the reviewed `main` history.
Confirm that the repository owner and URL in local Git configuration are the
intended public destination before setting `origin`.

Under **Settings → Actions → General → Workflow permissions**, select read
permissions by default and enable **Allow GitHub Actions to create and approve
pull requests**. The source updater needs that repository-level switch to open
its branch. It then explicitly dispatches `build.yml`, because events created
with the workflow token do not start another workflow automatically.

Release maintainers should also enable GitHub private vulnerability reporting
when available and keep Actions artifact attestations permitted for public
tag builds. Enable Dependabot alerts and security updates, and protect the
`v*` tag namespace so only release maintainers can create or update release
tags. See the [security policy](../SECURITY.md) for the reporting and trust
model.

The monthly release needs two settings beyond that default-read baseline. It
grants its own `contents: write` per job, so no repository-wide change is
required, but rulesets still apply to the workflow token:

- the `v*` tag ruleset must allow the GitHub Actions token to create tags, or
  the monthly run builds everything and then fails at the tag step. Add
  Actions to the ruleset bypass list, or accept tag-push releases only and
  turn the monthly schedule off;
- `automation/monthly-release` must be creatable and force-updatable. Scope
  branch protection to `main` rather than all branches.

Nothing here lets the automation write to `main`. The candidate commit lives
on its own branch, and the reviewed source-update PR remains the only way
refreshed pins reach the default branch.
