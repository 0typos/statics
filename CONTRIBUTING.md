# Contributing

Contributions should preserve the repository's core contract: reviewed and
pinned inputs produce reproducible, static Linux troubleshooting payloads
without committing generated binaries.

Start with the [building guide](docs/BUILDING.md), the
[architecture matrix](docs/ARCHITECTURES.md), and the
[security policy](SECURITY.md).

## Development workflow

Create a focused branch, make the smallest coherent change, and run:

```console
./scripts/validate.sh
shellcheck scripts/*.sh scripts/builders/*.sh scripts/lib/*.sh scripts/toolchain/*
make build ARCH=x86_64
make smoke ARCH=x86_64
```

ShellCheck is also run in CI. A full local matrix is welcome but not required
for every documentation-only change. Architecture-sensitive build changes
should cover representative 64-bit, 32-bit, and opposite-endian targets
before review; CI remains the complete matrix gate.

Do not add files from `.build/` or `dist/`. Those are generated outputs and
workflow artifacts.

## Repository map

| Path | Responsibility |
| --- | --- |
| `architectures.tsv` | Target name, Zig triple/CPU, QEMU runner, and description |
| `sources.lock` | Pinned upstream/toolchain version, SHA-256, and URL |
| `components.tsv` | Component license expression and role in the bundle |
| `docker/Dockerfile` | Clean toolchain, source, build, test, and export stages |
| `scripts/build.sh` | Target environment and build orchestration |
| `scripts/builders/` | One source-oriented recipe per component |
| `scripts/lib/build-common.sh` | Shared cross-build, install, and link helpers |
| `scripts/verify.sh` | Artifact contract, static checks, checksums, and QEMU smoke tests |
| `scripts/check-docs.py` | Markdown structure and repository-local link checks |
| `configs/` and `patches/` | Reviewed build configuration and minimal compatibility patches |
| `.github/workflows/` | Validation, matrix build, release, and source-update automation |
| `docs/` | User, maintainer, architecture, release, and roadmap documentation |

The TSV files are deliberately simple source-of-truth manifests. Keep prose
derived from them accurate, but do not create a second version manifest in
documentation.

## Add a tool

A tool should satisfy the selection criteria in
[the roadmap](docs/ROADMAP.md). Before implementation, determine its runtime
data, plugin, license, privilege, kernel, and static-dependency requirements.

Use this checklist:

1. Add the release archive to `sources.lock` with its exact version, URL, and
   SHA-256.
2. Add the component and SPDX license expression to `components.tsv`.
3. Add a builder in `scripts/builders/`. Cross-build only; never execute a
   target binary during compilation.
4. Add the source directory, builder import, and build call to
   `scripts/build.sh`.
5. Copy all required license and notice files in
   `scripts/collect-licenses.sh`.
6. Add every required executable, symbolic link, and runtime data file to the
   artifact checks in `scripts/verify.sh`.
7. Add a safe QEMU version/smoke check where the target supports one.
8. Add an upstream-release discoverer to `scripts/update_sources.py`, or
   document why the source cannot be updated automatically.
9. Document the tool's feature profile, intentional omissions, runtime data,
   privileges, and license caveats in `docs/TOOLKIT.md`.
10. Build and smoke-test representative architectures.

Prefer disabling an optional integration to silently depending on a target
shared library. If the utility cannot be useful without data files or plugins,
package and checksum them explicitly.

New patches need a short comment explaining the upstream incompatibility and
why the patch is safe for cross-compilation. Keep generated Autotools changes
out of the repository unless they are the reviewed fix.

## Add an architecture

Add one record to `architectures.tsv` only after confirming:

- Zig supports the target triple and intended minimum CPU;
- the ABI names word size, endianness, and float behavior unambiguously;
- a QEMU user-mode runner exists for smoke checks;
- every component cross-compiles without running target probes;
- the complete artifact passes static inspection and QEMU checks;
- the new target's limitations are documented in
  `docs/ARCHITECTURES.md`.

Update the explicit matrix in `.github/workflows/build.yml`. A local build
being successful is not sufficient: test startup, licenses, runtime data,
checksums, and the complete executable contract.

Do not broaden an existing target's CPU baseline casually. A more optimized
variant should normally be a new, clearly named target.

## Update pinned sources

Check one supported upstream without changing the lock:

```console
./scripts/update_sources.py --check --only nmap
```

Write a reviewed candidate update:

```console
./scripts/update_sources.py --write --only nmap
git diff -- sources.lock
```

The updater downloads the proposed archive to compute its SHA-256. Review
upstream release notes, published checksums, signatures when available,
license changes, and archive provenance. Then run the relevant builds and
verification. A new digest is not evidence by itself that an update is safe.

The weekly automation follows this same pattern and opens a pull request. It
must not be auto-merged.

## Change a build profile

Document both what is enabled and what is intentionally omitted. Consider:

- output size on constrained devices;
- target kernel and syscall requirements;
- shared libraries, plugin directories, CA stores, and databases;
- license changes introduced by optional dependencies;
- whether a meaningful smoke test can run without privileges;
- behavior across 32-bit, big-endian, and soft-float targets.

If a feature is useful but costly or incompatible across the whole matrix,
propose a separate profile rather than weakening the portable default.

## Documentation expectations

Commands in documentation should be copyable, non-destructive by default,
and explicit about required privileges. Link to source-of-truth files instead
of copying version numbers. Update the README when the project's public
contract changes and the focused guide when implementation detail changes.

Use relative Markdown links so documentation works both on GitHub and in a
clone.

## Pull request checklist

- The change has one clear purpose.
- Generated binaries and source archives are not committed.
- Inputs are pinned and checksum-verified.
- License notices and SBOM relationships remain complete.
- `./scripts/validate.sh` and ShellCheck pass.
- Relevant targets build and smoke-test.
- Runtime and architecture limitations are documented.
- The PR explains any check that could not be run locally.
