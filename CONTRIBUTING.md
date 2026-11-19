# Contributing

Contributions should preserve the repository's core contract: reviewed and
pinned inputs produce reproducible, static Linux troubleshooting payloads
without committing generated binaries.

Start with the [building guide](docs/BUILDING.md), the
[architecture matrix](docs/ARCHITECTURES.md), and the
[security policy](SECURITY.md).

## Contribution license

Unless a contribution explicitly states otherwise and is accepted on that
basis, contributions to this repository's original build recipes, scripts,
configuration, and documentation are made under the repository's
[MIT License](LICENSE). Contributions derived from an upstream project,
including patches to upstream code, must also comply with that project's
license.

This does not change the license of any upstream project. Do not copy upstream
code, generated files, or patches into the repository without preserving and
documenting their applicable terms.

## Development workflow

Create a focused branch, make the smallest coherent change, and run:

```console
make check
make build ARCH=x86_64
make smoke ARCH=x86_64
```

Changes to `tunpipe/` also need `./scripts/test-tunpipe.sh dist/x86_64` on a
host with unprivileged user namespaces. Containers usually lack them; CI runs
it on the x86-64 build's VM.

ShellCheck is also run in CI. A full local matrix is welcome but not required
for every documentation-only change. Architecture-sensitive build changes
should cover representative 64-bit, 32-bit, and opposite-endian targets
before review; CI remains the complete matrix gate.

Do not add files from `.build/` or `dist/`. Those are generated outputs and
workflow artifacts.

## Repository map

| Path | Responsibility |
| --- | --- |
| `architectures.tsv` | Target name, Zig triple/CPU, QEMU runner, description, and Go environment (or `none`) |
| `sources.lock` | Pinned upstream/toolchain version, SHA-256, and URL |
| `components.tsv` | Component license expression, role, archive (`main`, `extra`, or `both` for a library linked into each), and Go main packages with any build flags |
| `docker/Dockerfile` | Clean toolchain, source, build, test, and export stages |
| `scripts/build.sh` | Target environment, including the hermetic Go settings, and build orchestration |
| `scripts/components.sh` | The components that belong in one archive of one target |
| `scripts/fetch-go-modules.sh` | Downloads the Go modules the Go tools import, against each `go.sum` |
| `scripts/builders/` | One source-oriented recipe per component |
| `scripts/lib/build-common.sh` | Shared cross-build, install, and link helpers |
| `scripts/verify.sh` | Artifact contract, static checks, checksums, and QEMU smoke tests |
| `scripts/check-docs.py` | Markdown structure and repository-local link checks |
| `configs/` and `patches/` | Reviewed build configuration and minimal compatibility patches; `patches/go-mains/` holds Go main packages added to an upstream tree |
| `scripts/docker-build.sh` | Runs one Dockerfile target with the published toolchain image as a layer cache |
| `.circleci/config.yml` | All CI and releases: validation, matrix, sources, the required `ci-ok` status, signing, publishing, schedules, and the toolchain image |
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
2. Add the component, SPDX license expression, archive, and Go main packages
   (`-` for a non-Go tool) to `components.tsv`. Small core tools go in the
   `main` archive; large tools go in `extra`. A C tool's builder installs
   with `install_component_binary` so it lands in that archive; a library
   it links that main tools link too is marked `both`.
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

A Go tool's builder calls `go_build COMPONENT PACKAGE BINARY` from
`scripts/lib/build-common.sh`, and `scripts/build.sh` adds it to the DAG only
where `architectures.tsv` gives a Go environment. The go-modules stage fetches
its modules from the main packages listed in `components.tsv`; the build is
offline. `go_build` installs into the archive `components.tsv` names and
collects every linked module's license files, failing if a module has none.
Do not commit `vendor/` directories, and build with the upstream `go.sum`.
Build flags such as `-tags=...` go before the packages in `components.tsv`,
so the module fetch sees the same import graph as the build. To trim a large
tool, prefer upstream's own build tags; failing that, add a smaller main
package under `patches/go-mains/<source>/`, as for rclone, rather than
patching upstream code.

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

Update the explicit matrices in `.circleci/config.yml`; `scripts/validate.sh`
fails until every one matches
`architectures.tsv`. A local build
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

The updater downloads the proposed archive to compute its SHA-256, and for
rclone, croc, zstd, and nfs-utils (kernel.org's signed `sha256sums.asc`)
rejects it unless the release's own checksum file lists that digest. Check rclone's PGP-signed `SHA256SUMS` with
`gpg --verify SHA256SUMS` against the key published at
<https://rclone.org/KEYS>, and the signed tags of rclone and containerd.
stunnel's release must also match its published `.sha256`. Verify the
detached PGP signatures upstream publishes for libevent (Nick Mathewson,
`7A02B3521DC75C542BA015456AFEE6D49E92B601`), stunnel (Michał Trojnara,
`2BC7E4E67E3CC0C1BEA72F8C2EFC7FF0D416E014`), OpenVPN (security@openvpn.net,
`33DA8C9EAE0EAE8C73172C10822F6DF096D04874`), dnsmasq (Simon Kelley,
`D6EACBD6EE46B834248D111215CDDA6AE19135A2`), bash and readline (Chet Ramey,
`7C0135FB088AAF6C66C650B9BB5869F064EA74AB`), libssh2 (Daniel Stenberg,
`27EDEAF22F3ABCEB50DB9A125CC908FDB71E12C2`), lftp (Alexander V. Lukyanov,
`C027FA3148652A5513036413A824BB69F2A99A18`), expat (Sebastian Pipping,
`CB8DE70A90CFBF6C3BF5CC5696262ACFFBD3AEC6`), cifs-utils (its distribution
verification key, `C699981A31F338706C817650DF5BA9D30642D5A0`), nfs-utils
(Steve Dickson, `FEFAD1BB14447F4968C1971095D24347967C393E`; the signature
covers the uncompressed tar), and par2cmdline (Ike Devolder,
`DB2277BCD500AA3825610BDDDB323392796CA067`), for example with keys
fetched from `hkps://keyserver.ubuntu.com`. Review
upstream release notes, published checksums, signatures when available,
license changes, and archive provenance. Then run the relevant builds and
verification. A new digest is not evidence by itself that an update is safe.

`make update-sources` follows this same pattern and opens a pull request. It
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
- New repository-authored material is compatible with the MIT license.
- License notices and SBOM relationships remain complete.
- `make check` passes.
- Relevant targets build and smoke-test.
- Runtime and architecture limitations are documented.
- The PR explains any check that could not be run locally.
