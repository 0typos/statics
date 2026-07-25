# Building

The supported build path is Docker Buildx. It supplies the pinned Zig
toolchain, checksum-verified source trees, build dependencies, and QEMU
without modifying the host. The build does not download precompiled target
binaries and does not write generated binaries to Git.

## Prerequisites

For the normal container build, install:

- Git and GNU Make;
- Docker Engine or Docker Desktop with the Buildx plugin;
- an `amd64` or `arm64` Docker host;
- enough storage for the builder layers and source trees (allow roughly
  8 GB for an uncached build);
- outbound access to the source URLs in `sources.lock` on the first build.

Confirm the container tooling before starting:

```console
docker version
docker buildx version
docker buildx inspect --bootstrap
```

The Dockerfile currently packages Zig for `amd64` and `arm64` build hosts.
That restriction applies to the machine running Docker, not to the target:
either host can produce every architecture listed by `make list`.

## Choose a target

```console
make list
```

Do not select an embedded target from `uname -m` alone. ARM float ABI, MIPS
endianness, PowerPC word size, and the minimum CPU matter. Use the
[architecture and ABI guide](ARCHITECTURES.md) to inspect the destination
before building.

## Build one architecture

```console
make build ARCH=x86_64
```

Buildx exports the result to `dist/x86_64/`. Repeating the command reuses
Docker layers when the inputs have not changed and replaces that target's
output. Other target directories under `dist/` are left in place.

The first build is the slow path because it downloads the base image,
toolchain, and every pinned source archive. Later builds normally reuse the
BuildKit cache.

## What each command does

| Command | Result |
| --- | --- |
| `make build ARCH=<arch>` | Builds one target and exports `dist/<arch>/` |
| `make smoke ARCH=<arch>` | Builds one target, verifies it under QEMU in the container, and loads a local test image; it does not export `dist/<arch>/` |
| `make verify ARCH=<arch>` | Verifies an existing `dist/<arch>/` on the host |
| `make package ARCH=<arch>` | Rebuilds one target, then creates its archive, SBOM copy, and checksum files |
| `make all` | Builds and exports every target sequentially |
| `make smoke-all` | Builds and smoke-tests every target sequentially |
| `make sources` | Exports all pinned, checksum-verified upstream archives to `dist/sources/` |
| `make source-package` | Exports and packages the upstream archives as `dist/statics-sources.tar.xz` |
| `make clean` | Removes `.build/` and `dist/` |

Use `make help` as the concise command reference. `ARCH=x86_64` is the default,
but specifying it in scripts makes intent clearer.

## Verify a build

The simplest complete check is containerized:

```console
make smoke ARCH=mipsel
```

It checks manifests and licenses, validates every runtime payload checksum,
inspects every executable for static linkage and the absence of an ELF
interpreter, and runs representative version or smoke commands with the
target's QEMU user-mode emulator.

To verify an exported tree instead:

```console
make build ARCH=mipsel
make verify ARCH=mipsel
```

Host verification needs Bash, Python 3, `file`, `readelf`, GNU core utilities,
and the QEMU user executable named in `architectures.tsv`. On Debian-family
hosts, the emulator is normally supplied by `qemu-user-static`. The sole
native fast path currently implemented is `x86_64` on an `x86_64` host; other
targets require their named QEMU runner even when the host has the same CPU.

Set `SKIP_QEMU=1` only when execution is impossible and static inspection is
still useful:

```console
SKIP_QEMU=1 make verify ARCH=powerpc
```

That is a reduced check, not equivalent to the CI gate.

## Package and inspect an artifact

```console
make package ARCH=aarch64
cd dist
sha256sum --check statics-aarch64.tar.xz.sha256
tar -tJf statics-aarch64.tar.xz
```

The package command creates:

```text
dist/
├── aarch64/
├── statics-aarch64.tar.xz
├── statics-aarch64.tar.xz.sha256
├── statics-aarch64.spdx.json
└── statics-aarch64.spdx.json.sha256
```

The archive contains one top-level directory named for the target. Its layout
is:

```text
aarch64/
├── busybox, nmap, ncat, rsync, lsof, ...
├── share/nmap/
├── licenses/<upstream>/
├── BUILDINFO
├── BUILD_RECIPES_LICENSE
├── COMPONENTS.tsv
├── SBOM.spdx.json
├── SHA256SUMS
├── THIRD_PARTY_NOTICES.md
└── sources.lock
```

`SHA256SUMS` covers all executable payloads and Nmap runtime data.
`SBOM.spdx.json` records the same payload plus its upstream package
relationships. License texts and build metadata remain alongside the payload
but are not entries in `SHA256SUMS`.

`BUILD_RECIPES_LICENSE` is the MIT license for this repository's original
build machinery. It does not apply to the bundled utilities. Their individual
terms are indexed by `COMPONENTS.tsv` and packaged under `licenses/`.

Archives are normalized for stable ordering, ownership, and timestamps.
Reproducibility still depends on identical repository inputs, source
archives, builder images, and toolchain. CI confirms this by comparing two
uncached x86-64 output trees.

## Deploy a bundle

Extract the archive on a staging machine or directly on the destination:

```console
tar -xJf statics-aarch64.tar.xz
scp -r aarch64 device:/tmp/statics
```

Run tools by absolute path or put the directory first in a temporary `PATH`:

```console
export PATH=/tmp/statics:$PATH
ip -brief address
ss -listening -numeric -tcp
```

Keep `share/nmap/` with the executable and pass its location explicitly:

```console
nmap --datadir /tmp/statics/share/nmap --version
```

See the [toolkit guide](TOOLKIT.md) for field-use examples, feature profiles,
and privilege requirements.

## Source bundles

```console
make source-package
sha256sum --check dist/statics-sources.tar.xz.sha256
```

The resulting archive contains the exact upstream archives and `sources.lock`
used by the recipes. It supports source review and corresponding-source
obligations. It is not currently an offline input format for the Dockerfile;
an offline/restricted-network build workflow would need a separately
documented cache import mechanism.

## Alternate container commands

The executable used by the Makefile can be overridden:

```console
make build ARCH=x86_64 DOCKER=/path/to/docker
```

The replacement must implement the Buildx commands and local-output semantics
used by the Makefile. Docker Buildx is the tested interface; other container
CLIs are not part of the current compatibility contract.

`scripts/build.sh` is the internal build orchestrator. Calling it directly
requires the pinned Zig release, all build dependencies, and every extracted
source tree under `/src` (or `SOURCES_DIR`). It is intentionally not the
recommended host setup.

If a command fails, start with the
[troubleshooting guide](TROUBLESHOOTING.md).
