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

The Dockerfile currently packages Zig and Go for `amd64` and `arm64` build hosts.
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
| `make package ARCH=<arch>` | Rebuilds one target, then creates its archive, SBOM copy, and checksum files, and the same for its extra archive when it has one |
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
`xz`, `bzip2`, `gzip`, and the QEMU user executable named in
`architectures.tsv`. On Debian-family
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
├── share/nmap/, share/testssl/
├── licenses/<upstream>/
├── BUILDINFO
├── BUILD_RECIPES_LICENSE
├── COMPONENTS.tsv
├── SBOM.spdx.json
├── SHA256SUMS
├── THIRD_PARTY_NOTICES.md
└── sources.lock
```

Go tools add `licenses/<tool>/go-modules.tsv`, the modules linked into the
tool as read from its own build info, and each module's license and notice
files under `licenses/<tool>/modules/<module>@<version>/`. The Go runtime's
notices are under `licenses/go/`.

`SHA256SUMS` covers all executable payloads and the Nmap and testssl.sh
runtime data under `share/`.
`SBOM.spdx.json` records the same payload plus its upstream package
relationships. License texts and build metadata remain alongside the payload
but are not entries in `SHA256SUMS`.

`BUILD_RECIPES_LICENSE` is the MIT license for this repository's original
build machinery. It does not apply to the bundled utilities. Their individual
terms are indexed by `COMPONENTS.tsv` and packaged under `licenses/`.

### Extra archive

Large tools go in a second archive, `statics-extra-<arch>.tar.xz`, so the
main kit stays small. `components.tsv` assigns each component to `main` or
`extra`, or to `both` for a library linked into tools in each archive (OpenSSL
and libcap-ng), whose notices and SBOM entry then appear in each. The extra archive has the same layout and metadata as the main one,
under a top-level `<arch>-extra/` directory, with its own `SHA256SUMS`,
`COMPONENTS.tsv`, notices, and SBOM (`statics-extra-<arch>.spdx.json`). It
exists only for an architecture that builds at least one extra tool: today
`stunnel` and `openvpn` on every target, and `rclone`, `croc`, `crictl`, and
`ctr` on every target with Go. A C tool's builder installs with
`install_component_binary`, which, like `go_build`, puts it in the archive
`components.tsv` names. It is
compressed with `xz -9` rather than the main archive's `-6`: the 64 MiB
window spans all the binaries, which share Go's runtime and many modules,
or OpenSSL, and makes the archive about 30% smaller, at about 65 MiB of memory to
decompress.

`components.tsv` may list `go build` flags before a Go tool's packages, such
as croc's `-tags=croc_no_tailcat`; the module fetch and `go_build` both use
them. A main package this repository adds to an upstream tree, such as
rclone's trimmed `./cmd/statics`, lives under `patches/go-mains/<source>/`
and is copied into that source tree by the module fetch and by `build.sh`,
so the upstream `go.mod` and `go.sum` still govern it.

Archives are normalized for stable ordering, ownership, and timestamps.
Reproducibility still depends on identical repository inputs, source
archives, builder images, and toolchain. CI checks this on releases and on a
manual `task=reproducibility` run, and `make repro` locally, by comparing the x86-64
archive it ships, which may come from cached layers, with an independent
rebuild without cache at twice the `make -j`; a release rebuilds the
toolchain as well. Pull requests and pushes skip the rebuild for speed, so a
change that breaks reproducibility surfaces at the next `make repro` or
release rather than on its pull request.

The builder's Debian packages come from the snapshot.debian.org date that
the pinned base image records, so the base digest alone fixes them and a
cached layer can never hold different packages than a fresh rebuild.
`BUILDINFO` records that snapshot and a digest of the installed package
list. Bumping the base image digest moves the snapshot with it.

CI does not rebuild the toolchain stage in every job. The `Toolchain image`
workflow builds it from scratch on `main` and publishes it as
`ghcr.io/0typos/statics-toolchain:main`, and every CI build pulls it as a
layer cache through `scripts/docker-build.sh`. It is never a `FROM`: the
Dockerfile remains the only definition, BuildKit reuses the image's layers
only when they match what the Dockerfile would build, and a missing image
just means the stage is built locally. The same workflow publishes each
architecture's shared libraries (OpenSSL, libpcap, libmnl, libcap-ng: the
`deps` stage) as `statics-toolchain:deps-<arch>`, which CI's matching builds
also pull; local builds pass no `COMPONENT_TIMEOUT` and so build them.
Releases never use these images. `TOOLCHAIN_IMAGE=''` disables both.

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
used by the recipes, the Go source release the pinned toolchain was built
from, and under `go-modules/` every Go module the Go tools link, in Go module
proxy layout. It supports source review and corresponding-source
obligations. It is not currently an offline input format for the Dockerfile;
an offline/restricted-network build workflow would need a separately
documented cache import mechanism. The Go part already works offline; for
example, from wireguard-go's extracted source tree:

```console
tar -xJf dist/statics-sources.tar.xz -C /tmp
GOPROXY=file:///tmp/sources/go-modules GOFLAGS=-mod=readonly \
    go build -o wireguard-go .
```

The module tree holds only what the bundled tools link, so build the same
packages with the same flags: rclone's `./cmd/statics` after copying in
`patches/go-mains/rclone/`, croc with `-tags=croc_no_tailcat`, `./cmd/crictl`,
and `./cmd/ctr`, adding the `-X` version flags from `scripts/builders/` for
the same version strings. Upstream's full rclone build needs modules that are
not in the bundle.

## Go tools and network access

Go tools are built by the Go release pinned as `go-x86_64` and `go-aarch64`
in `sources.lock`, from go.dev rather than Debian. The Dockerfile's
`go-modules` stage, built on the sources stage, is the only step with network
access for Go: `scripts/fetch-go-modules.sh` asks the
module proxy for exactly the modules each tool's main packages import on
Linux, for every Go architecture, with `-mod=readonly`, so each upstream
`go.sum` (inside its pinned source archive) must already list them and every
download must match it.

The compile step then runs with `RUN --network=none`, for the C tools as
well, and with `CGO_ENABLED=0 GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off
GOWORK=off GOENV=off` and `GOFLAGS="-mod=readonly -trimpath -buildvcs=false"`.
A missing module, a `go.sum` mismatch, or a `go.mod` that asks for a newer Go
fails the build instead of downloading anything. Binaries are linked with
`-ldflags="-s -w -buildid="`; UPX is not used.

## Alternate container commands

The executable used by the Makefile can be overridden:

```console
make build ARCH=x86_64 DOCKER=/path/to/docker
```

The replacement must implement the Buildx commands and local-output semantics
used by the Makefile. Docker Buildx is the tested interface; other container
CLIs are not part of the current compatibility contract.

`scripts/build.sh` is the internal build orchestrator. Calling it directly
requires the pinned Zig and Go releases, all build dependencies, every
extracted source tree under `/src` (or `SOURCES_DIR`), and the Go module
cache that `scripts/fetch-go-modules.sh` writes there. It is intentionally not the
recommended host setup.

If a command fails, start with the
[troubleshooting guide](TROUBLESHOOTING.md).
