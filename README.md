# statics

Reproducible, cross-architecture Linux troubleshooting binaries. This
repository contains the build recipes, source pins, CI, verification, and
release machinery—not generated binaries. Build outputs are local files,
GitHub Actions artifacts, or release assets.

Published binaries are rebuilt automatically every month. A scheduled workflow
repins every component to its latest upstream release, rebuilds all thirteen
architectures, and publishes a new GitHub Release once every verification gate
passes. Months with no upstream or recipe change are skipped rather than
republished, so the newest release is always the newest set of inputs that
actually built and verified. See [Automation](#automation).

Every target is compiled against musl with a pinned
[Zig](https://ziglang.org/) toolchain. Docker provides the clean build
environment, and QEMU user-mode emulation provides an execution smoke test for
non-native architectures.

## Quick start

Requirements: Git, GNU Make, Docker with Buildx, roughly 8 GB of free disk
space for the first build, and an `amd64` or `arm64` Docker host.

```console
# Clone this repository using the URL shown by your Git host, then:
cd statics
make smoke ARCH=x86_64
make build ARCH=x86_64
```

`make smoke` performs a containerized cross-build and runs representative
commands under QEMU. `make build` reuses those cached layers and exports the
toolkit under `dist/x86_64/`.

```console
make list                     # show the complete target matrix
make build ARCH=mipsel        # build one target
make package ARCH=mipsel      # build and create dist/statics-mipsel.tar.xz
make verify ARCH=mipsel       # verify an existing exported build
make all                      # build every target
make sources                  # export all checksum-verified source archives
make source-package           # create dist/statics-sources.tar.xz
```

`make help` is the command reference. Generated files live under `dist/` and
`.build/`; both are ignored by Git.

## Documentation

| Guide | Use it for |
| --- | --- |
| [Building](docs/BUILDING.md) | Prerequisites, exact Make targets, artifact layout, verification, packaging, and deployment |
| [Toolkit](docs/TOOLKIT.md) | Command examples, feature profiles, omissions, runtime data, and privileges |
| [Architectures](docs/ARCHITECTURES.md) | Device identification, ABI selection, and QEMU coverage |
| [Troubleshooting](docs/TROUBLESHOOTING.md) | Build, QEMU, architecture, permission, CA, Nmap, Lsof, and rsync failures |
| [Contributing](CONTRIBUTING.md) | Adding a tool or target, updating sources, validation, and review expectations |
| [Releasing](docs/RELEASING.md) | Release gates, assets, checksums, tags, and attestations |
| [Security](SECURITY.md) | Supply-chain trust, artifact guarantees, and operational safety |
| [Roadmap](docs/ROADMAP.md) | Candidate utilities, profiles, and deferred platforms |

## Toolkit

The bundle contains 44 physical executables plus BusyBox and Dropbear
multi-call links, Nmap runtime data, checksums, an SPDX SBOM, and upstream
license texts.

| Area | Outputs | Notes |
| --- | --- | --- |
| Rescue userspace | `busybox`, `nc`, `netcat` | Full BusyBox defconfig and convenient network applet links |
| Remote access, relays, and transfer | `socat`, `ncat`, `rsync`, `dropbear`, `dbclient`, `scp` | Dropbear also supplies key and conversion tools; zlib is disabled |
| Network state and control | `ip`, `ss`, `bridge`, `tc`, `wg`, `ethtool` | iproute2 and ethtool include static libmnl netlink support |
| Discovery, packet, and path diagnosis | `nmap`, `tcpdump`, `iperf3`, `mtr`, `mtr-packet` | Nmap and tcpdump use static libpcap; mtr is built without curses |
| HTTP, TLS, DNS, and data | `curl`, `openssl`, `drill`, `jq` | TLS-capable tools share the pinned OpenSSL build |
| Process diagnosis | `strace`, `lsof` | Syscall tracing plus process/file/socket correlation through Linux procfs |
| Namespaces and privilege | `nsenter`, `unshare`, `lsns`, `setpriv`, `findmnt` | Enter, create, enumerate, constrain, and inspect Linux namespace state |
| CAN and ISO-TP | `candump`, `cansend`, `cangen`, `canplayer`, `cansniffer`, `isotpdump`, `isotprecv`, `isotpsend`, `slcand`, `canbusload` | SocketCAN tools for field and vehicle networks |
| Hardware buses | `i2cdetect`, `i2cdump`, `i2cget`, `i2cset`, `i2ctransfer`, `spi-config`, `spi-pipe` | Direct Linux I²C and spidev diagnosis |

Convenience links expose useful BusyBox applets such as `ping`, `traceroute`,
`nslookup`, `arping`, `wget`, `ifconfig`, and `netstat`. They do not add extra
binary payload.

The portable default intentionally disables selected optional integrations.
In particular, keep Nmap's packaged `share/nmap/` directory with the
executable, provide curl a trusted CA bundle when the target lacks one, and do
not expect rsync to preserve ACLs or extended attributes. Nmap and Ncat are
governed by the Nmap Public Source License, so review their packaged terms
before deployment or redistribution.

Static linking does not grant permissions or provide missing kernel support.
Packet capture, raw probes, network changes, process tracing, and hardware-bus
access still require the corresponding Linux capabilities, drivers, device
nodes, and security policy. The [toolkit guide](docs/TOOLKIT.md) documents
each profile and gives safe starting commands.

`setns(2)` is a Linux system call rather than a separate standard utility.
The bundled util-linux `nsenter` is its maintained command-line interface.
`unshare`, `lsns`, `setpriv`, and `findmnt` cover the adjacent creation,
enumeration, privilege, and mount-view workflows.

## Supported Linux targets

The matrix covers:

- x86-64 and 32-bit x86
- AArch64
- ARMv6 hard-float and ARMv7 soft/hard-float
- 32-bit MIPS in both endian modes
- 32/64-bit PowerPC in big-endian and little-endian modes
- RISC-V 64 and s390x

See the [architecture and ABI guide](docs/ARCHITECTURES.md) before selecting a
device build. A successful static build does not replace kernel support for
required system calls, network families, TUN, namespaces, packet sockets, or
device ioctls.

## Reproducibility and source trust

[`sources.lock`](sources.lock) pins every compiler and upstream source archive
by version, URL, and SHA-256. Fetches fail closed on a checksum mismatch.
Builds set a fixed `SOURCE_DATE_EPOCH`, remove debug/symbol tables with Zig's
cross-linker flags, and emit:

- `BUILDINFO` with the target and component versions
- `SHA256SUMS` for every executable payload and Nmap runtime data file
- the exact `sources.lock` used by the build
- `COMPONENTS.tsv` and a deterministic SPDX 2.3 SBOM
- complete upstream notices under `licenses/`
- the build-recipe MIT license as `BUILD_RECIPES_LICENSE`

Most upstreams are fetched over HTTPS. Socat is the documented exception:
its canonical hostname does not have a matching TLS certificate, so its
release archive is fetched over HTTP and protected by the reviewed lock-file
digest. See [SECURITY.md](SECURITY.md) for the trust model and update policy.

The output contains GPL and other copyleft software. Binary bundles carry the
relevant upstream license texts and a generated `THIRD_PARTY_NOTICES.md`.
When redistributing artifacts, retain the build recipes and make corresponding
source available. `make source-package` produces the exact upstream archive
bundle used by a build.

## Licensing

Repository-authored build recipes, scripts, configuration, and documentation
are licensed under the [MIT License](LICENSE), unless a file says otherwise.
Patches or other material derived from an upstream project remain subject to
that project's terms.

That MIT license does not replace or override the licenses of the utilities,
libraries, or source archives built by this project. Each upstream project
retains its own copyright and license terms. [`components.tsv`](components.tsv)
indexes those terms, and every binary bundle includes
`THIRD_PARTY_NOTICES.md` plus the relevant texts under
`licenses/<source>/`. The repository's MIT license is included separately in
artifacts as `BUILD_RECIPES_LICENSE`.

Redistributors are responsible for complying with every applicable upstream
license, including corresponding-source obligations and Nmap's NPSL terms.
This repository does not relicense upstream code or generated binaries.

## Automation

GitHub Actions:

- validates shell/Python and manifest structure on every change;
- cross-builds the full architecture matrix;
- verifies static linking and runs each core utility under QEMU;
- uploads deterministic per-architecture archives as workflow artifacts;
- exports a matching source-archive artifact;
- independently rebuilds x86-64 twice and compares the complete outputs;
- publishes checksummed binaries, SPDX SBOMs, notices, and corresponding
  sources on `v*` tags;
- attaches GitHub/Sigstore provenance and SBOM attestations for public
  releases;
- rebuilds the pins weekly to catch toolchain or infrastructure regressions;
- checks upstream releases weekly and opens a checksum-refresh PR;
- repins, builds, and releases every architecture monthly, publishing only
  when every gate passes and skipping the build entirely when nothing has
  changed since the last release;
- keeps the most recent 24 monthly releases and removes the assets of older
  ones, without ever deleting a tag.

Dependabot maintains Docker and GitHub Actions references. Source updates are
kept separate because generic tarball releases are not a Dependabot ecosystem;
[`scripts/update_sources.py`](scripts/update_sources.py) is the lock-file
equivalent. Update PRs are intentionally not auto-merged: CI and review of
release notes/signatures remain required. The updater explicitly dispatches
the full build for its bot-created PR branch.

The monthly release publishes repinned upstream versions without that review,
which is the point of an unattended release and also its main caveat. It never
writes to `main`. See the [release guide](docs/RELEASING.md) to turn the
refresh off, disable the schedule, or read what the automation is allowed to
do.

See the [release guide](docs/RELEASING.md) for release gates, assets, and
attestation verification.

## Adding a tool or architecture

Tool recipes are isolated under `scripts/builders/`, and architecture
definitions live in one table, [`architectures.tsv`](architectures.tsv). The
[contribution guide](CONTRIBUTING.md) gives complete checklists for adding
either without weakening source, license, static-link, or verification
coverage.

The prioritized tool backlog and selection criteria are in
[docs/ROADMAP.md](docs/ROADMAP.md). Linux is the current contract. Darwin and
Windows are future, separate target families because their libc, executable
formats, networking APIs, and validation environments differ substantially.

## Prior art

This design draws useful ideas—and avoids the checked-in artifact model—from:

- [perryflynn/static-binaries](https://github.com/perryflynn/static-binaries)
- [andrew-d/static-binaries](https://github.com/andrew-d/static-binaries)
- [polaco1782/linux-static-binaries](https://github.com/polaco1782/linux-static-binaries)
- [ryanwoodsmall/static-binaries](https://github.com/ryanwoodsmall/static-binaries)
