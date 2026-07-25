# Security and supply-chain policy

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
- records versions and executable SHA-256 digests;
- records a deterministic SPDX SBOM and complete upstream notices;
- executes representative commands through QEMU;
- exports the exact source archives as a companion artifact.

CI also performs two independent uncached x86-64 builds and compares their
complete output trees. Tagged public releases receive GitHub/Sigstore
attestations linking each binary archive and SBOM to its workflow, repository,
and commit. Attestations establish provenance; they are not a claim that the
contents are vulnerability-free.

QEMU tests instruction set and ABI compatibility. It does not validate
privileged operations, device ioctls, a target's kernel configuration, or
behavior under its security policy.

## Operational safety

These utilities can listen on sockets, change network configuration, capture
or generate traffic, start an SSH server, and execute subprocesses. Use them
only on systems and networks where you are authorized to do so. Treat downloaded
workflow artifacts as release candidates until their provenance and digests
have been reviewed for the intended environment.

Do not configure automated merging for source update PRs without adding an
equivalent signature/provenance policy.
