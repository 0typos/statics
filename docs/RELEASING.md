# Release process

The `Build` workflow treats a signed or annotated `v*` tag as a release
candidate. A release is published only after:

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

For public repositories, the workflow attaches a GitHub/Sigstore SBOM
attestation to each binary archive and a provenance attestation to the
corresponding-source archive. Verify one with:

```console
gh attestation verify statics-x86_64.tar.xz --repo OWNER/REPOSITORY
```

## Creating a release

After the full `main` build is green:

```console
git tag -s vYYYY.MM.DD -m "vYYYY.MM.DD"
git push origin vYYYY.MM.DD
```

If signed tags are not available, use an annotated tag and document the
reason. Do not create a release from an unreviewed automated source-update
commit.

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
