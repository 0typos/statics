# Release process

Pushing any `v*` tag starts the `Build` workflow's release path. Project policy
requires a signed tag when available, or an annotated tag with the reason a
signature was unavailable. A GitHub Release is published only after:

1. repository validation and ShellCheck pass;
2. every architecture builds and passes static/QEMU verification;
3. two independent, uncached x86-64 builds have identical contents;
4. the corresponding-source archive is packaged;
5. every downloaded release asset passes its portable SHA-256 file.

The release contains, for every architecture:

- `statics-<arch>.tar.xz` and its SHA-256 file;
- a standalone deterministic SPDX 2.3 SBOM and its SHA-256 file.

It also contains `statics-sources.tar.xz` and its SHA-256 file. Binary
archives include `BUILDINFO`, `COMPONENTS.tsv`, `sources.lock`,
`THIRD_PARTY_NOTICES.md`, the SPDX SBOM, and all relevant upstream license
texts.

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

Never release directly from an unreviewed automated source-update branch.

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
`BUILDINFO`, `sources.lock`, `THIRD_PARTY_NOTICES.md`, and
`SBOM.spdx.json` inside the extracted target directory.

Re-running the tag workflow verifies the build again and replaces assets on
the existing GitHub Release. It does not bypass any build or reproducibility
gate.

## Repository settings

The default branch must require the `validate`, `reproducibility`, and all
architecture `build` checks before accepting changes. Keep force pushes and
branch deletion disabled.

Under **Settings → Actions → General → Workflow permissions**, select read
permissions by default and enable **Allow GitHub Actions to create and approve
pull requests**. The source updater needs that repository-level switch to open
its branch. It then explicitly dispatches `build.yml`, because events created
with the workflow token do not start another workflow automatically.

Release maintainers should also enable GitHub private vulnerability reporting
when available and keep Actions artifact attestations permitted for public
tag builds. See the [security policy](../SECURITY.md) for the reporting and
trust model.
