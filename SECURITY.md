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
not receive backported fixes unless maintainers announce otherwise.

## Build inputs

All upstream archives and both supported host toolchains are pinned by
SHA-256 in `sources.lock`. The Docker base/frontend images and every external
GitHub Action are also pinned to immutable digests or full commit SHAs.
A build stops before extraction when a source digest does not match.
Dependabot maintains Docker and GitHub Actions pins.

The scheduled source updater discovers stable releases and computes new
digests, but only opens a pull request. It does not merge, publish, or replace
an existing release. Reviewers should inspect upstream release notes, compare
published checksums, and verify upstream signatures where available.

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

CI also performs two independent uncached x86-64 builds and compares their
complete output trees. Tagged public releases receive GitHub/Sigstore
attestations linking each binary archive and SBOM to its workflow, repository,
and commit. Attestations establish provenance; they are not a claim that the
contents are vulnerability-free.

Consumers should verify the portable SHA-256 files and, for public releases,
the GitHub/Sigstore attestation before deployment. Exact commands are in the
[release guide](docs/RELEASING.md).

QEMU tests instruction set and ABI compatibility. It does not validate
privileged operations, device ioctls, a target's kernel configuration, or
behavior under its security policy.

## Operational safety

These utilities can listen on sockets, change network configuration, capture
or generate traffic, enter or create namespaces, alter a child process's
privilege state, start an SSH server, and execute subprocesses. Use them only
on systems and networks where you are authorized to do so. Treat downloaded
workflow artifacts as release candidates until their provenance and digests
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
- release artifacts can be tied to a public workflow and commit when
  attestations are enabled.

It does not guarantee that an upstream utility is vulnerability-free, that a
target kernel is secure or compatible, that QEMU covers privileged behavior,
or that granting broad capabilities to these utilities is safe. Nmap's
non-OSI license is a deployment/compliance consideration, not a security
attestation.

For runtime privilege boundaries and safer starting commands, see the
[toolkit guide](docs/TOOLKIT.md). For failures that can look like security
policy problems, see [troubleshooting](docs/TROUBLESHOOTING.md).
