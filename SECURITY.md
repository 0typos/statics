# Security and supply-chain policy

## Reporting a vulnerability

Use the repository's private vulnerability-reporting channel when it is
enabled. Otherwise contact the maintainers through a private address published
by the repository owner. Do not open a public issue for an unpatched
vulnerability or include secrets, private keys, packet captures, or customer
network details in a report.

Include the affected commit/tag and architecture, reproduction conditions,
impact, and whether the problem is in a build recipe, generated artifact, or
upstream component. Upstream vulnerabilities that are not introduced by this
repository may also need coordinated reporting to the upstream project.

The maintained security surface is the current default branch and the latest
published release. Older artifacts remain reproducible from their tags but do
not receive backported fixes unless maintainers announce otherwise. Prebuilt
assets are kept for the most recent 24 monthly releases; beyond that the
release and its downloads are removed while the tag is retained, so an expired
version stays buildable but is no longer distributed.

## Build inputs

All upstream archives and both supported host toolchains are pinned by
SHA-256 in `sources.lock`. The Docker base/frontend images, the CircleCI job
images, and the release tools (`gh`, `cosign`) are also pinned to immutable
digests or release checksums.
A build stops before extraction when a source digest does not match.
Dependabot maintains the Docker pins.

The builder's Debian packages are installed from the snapshot.debian.org date
that the pinned base image records, so the base digest fixes them too. They
are fetched over HTTP and accepted only with a valid Debian archive
signature. Snapshot Release files are past their `Valid-Until` by design, so
that freshness check is disabled: an on-path attacker could replay an older
signed Release, though not alter a package. `BUILDINFO` records the snapshot
and a digest of the installed package list, which exposes such a rollback.

CI pulls the toolchain stage from `ghcr.io/0typos/statics-toolchain:main` as a
layer cache. The `Toolchain image` workflow publishes it only from `main`, but
the package itself is writable by any workflow in this repository and by any
token with package write access, so it is not a trust boundary. BuildKit
reuses its layers wherever their cache keys match, so a planted toolchain
would reach the matrix build. Release builds therefore do not depend on it:
their reproducibility rebuild ignores the image and builds the toolchain from
scratch, so planted layers produce a mismatch and block the release. The
Dockerfile is the only definition of the toolchain, and any tag rebuilds from
the repository without the image.

The weekly source updater discovers stable releases and computes new digests,
but only opens a pull request. It does not merge into the default branch.
Reviewers should inspect upstream release notes, compare published checksums,
and verify upstream signatures where available.

The monthly release workflow is different and deserves explicit attention: it
repins to the latest upstream releases, builds them, and publishes the result
without a maintainer reading upstream release notes or verifying upstream
signatures first. Every mechanical gate still applies — digest pinning, static
linking, QEMU verification, reproducibility against a rebuild without cache,
SBOM, and Sigstore signatures —
so an automated release is as reproducible and as attributable as a manual
one. What it lacks is human judgement about the upstream code it pins. Those
releases are built from a commit on `automation/monthly-release`, never from
unreviewed changes to the default branch. Operators who need review before
publication should set `REFRESH_SOURCES` to `false` or disable the schedule;
see the [release guide](docs/RELEASING.md).

Socat is an explicit transport exception. Its canonical download host does not
present a certificate valid for the hostname, so the release archive is
fetched over HTTP. The lock digest prevents later substitution after review,
but the first checksum refresh is trust-on-first-review. Moving to a stable,
authenticated upstream mirror or automated signature validation is desirable.

## Artifact checks

Each build:

- uses a clean container and a pinned Zig release;
- links against musl with no ELF program interpreter;
- strips binaries with the same cross-aware toolchain;
- records versions and SHA-256 digests for executable payloads and Nmap
  runtime data;
- records a deterministic SPDX SBOM and complete upstream notices;
- executes representative commands through QEMU;
- exports the exact source archives as a companion artifact.

Every release also rebuilds x86-64 without any cache, toolchain included, and
requires the result to be byte-identical to the archive it ships. The weekly
scheduled build runs the same comparison on the published toolchain stage
(below); pull requests and pushes skip it for speed. Every release archive
carries Sigstore bundles, signed keylessly by the CircleCI release job through
its OIDC identity and logged in the public Rekor transparency log: SLSA
provenance tying the archive to its repository, tag, and commit, and, for
binary archives, the SBOM. They establish provenance; they are not a claim
that the contents are vulnerability-free.

Publishing credentials live in the only CircleCI context in the
organization, which only pipelines on `main` or a `v*` tag can use and SSH
reruns never get. A `v*` tag can be created only by a repository admin, so a
branch or pull request pipeline can neither publish nor sign as the release
job. Adding an unrestricted context to the organization would hand that
signing identity to every branch.

Consumers should verify the portable SHA-256 files and the Sigstore bundles
before deployment. Exact commands are in the
[release guide](docs/RELEASING.md).

QEMU tests instruction set and ABI compatibility. It does not validate
privileged operations, device ioctls, a target's kernel configuration, or
behavior under its security policy.

## Operational safety

These utilities can listen on sockets, change network configuration, capture
or generate traffic, enter or create namespaces, alter a child process's
privilege state, start an SSH server, and execute subprocesses. Use them only
on systems and networks where you are authorized to do so. Treat downloaded
CI artifacts as release candidates until their provenance and digests
have been reviewed for the intended environment.

Do not configure automated merging for source update PRs without adding an
equivalent signature/provenance policy.

## Security boundaries

The project aims to guarantee that:

- declared, checksum-pinned source inputs are used;
- produced ELF payloads are static and have no dynamic interpreter;
- required executables, runtime data, notices, and metadata are present;
- payload digests and the SPDX document are internally consistent;
- representative commands start under the target QEMU ABI;
- release artifacts can be tied to the CircleCI release job and commit
  through their Sigstore bundles.

It does not guarantee that an upstream utility is vulnerability-free, that a
target kernel is secure or compatible, that QEMU covers privileged behavior,
or that granting broad capabilities to these utilities is safe. Nmap's
non-OSI license is a deployment/compliance consideration, not a security
attestation.

For runtime privilege boundaries and safer starting commands, see the
[toolkit guide](docs/TOOLKIT.md). For failures that can look like security
policy problems, see [troubleshooting](docs/TROUBLESHOOTING.md).
