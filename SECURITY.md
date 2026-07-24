# Security and supply-chain policy

## Build inputs

All upstream archives and both supported host toolchains are pinned by
SHA-256 in `sources.lock`. A build stops before extraction when a digest does
not match. Docker and GitHub Actions dependencies are maintained separately by
Dependabot.

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
- executes representative commands through QEMU;
- exports the exact source archives as a companion artifact.

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
