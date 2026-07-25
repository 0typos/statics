# statics

Reproducible, cross-architecture Linux troubleshooting binaries. The
repository contains build recipes, source pins, CI, and tests—not generated
binaries.

Every target is compiled against musl with a pinned
[Zig](https://ziglang.org/) toolchain. Docker provides the clean build
environment, and QEMU user-mode emulation provides an execution smoke test for
non-native architectures.

## Quick start

Requirements:

- Docker with Buildx
- roughly 8 GB of free disk space for the first build
- an `amd64` or `arm64` Docker host

```console
git clone <this-repository>
cd statics
make build ARCH=x86_64
make smoke ARCH=x86_64
```

The first command writes files under `dist/x86_64/`. The second performs the
same clean build and runs its outputs under QEMU in the build container.

```console
make list                     # show the complete target matrix
make build ARCH=mipsel        # build one target
make package ARCH=mipsel      # build and create dist/statics-mipsel.tar.xz
make all                      # build every target
make sources                  # export all checksum-verified source archives
make source-package           # create dist/statics-sources.tar.xz
```

`make help` is the command reference. Generated files live under `dist/` and
`.build/`; both are ignored by Git.

## Toolkit

The bundle contains 39 physical executables, plus BusyBox and Dropbear
multi-call links.

| Area | Outputs | Notes |
| --- | --- | --- |
| Rescue userspace | `busybox`, `nc`, `netcat` | Full BusyBox defconfig and convenient network applet links |
| Remote access, relays, and transfer | `socat`, `ncat`, `rsync`, `dropbear`, `dbclient`, `scp` | Dropbear also supplies key and conversion tools; zlib is disabled |
| Network state and control | `ip`, `ss`, `bridge`, `tc`, `wg`, `ethtool` | iproute2 and ethtool include static libmnl netlink support |
| Discovery, packet, and path diagnosis | `nmap`, `tcpdump`, `iperf3`, `mtr`, `mtr-packet` | Nmap and tcpdump use static libpcap; mtr is built without curses |
| HTTP, TLS, DNS, and data | `curl`, `openssl`, `drill`, `jq` | curl, iperf3, and drill use the pinned OpenSSL build |
| Process diagnosis | `strace`, `lsof` | Syscall tracing plus process/file/socket correlation through Linux procfs |
| CAN and ISO-TP | `candump`, `cansend`, `cangen`, `canplayer`, `cansniffer`, `isotpdump`, `isotprecv`, `isotpsend`, `slcand`, `canbusload` | SocketCAN tools for field and vehicle networks |
| Hardware buses | `i2cdetect`, `i2cdump`, `i2cget`, `i2cset`, `i2ctransfer`, `spi-config`, `spi-pipe` | Direct Linux I²C and spidev diagnosis |

Convenience links expose useful BusyBox applets such as `ping`, `traceroute`,
`nslookup`, `arping`, `wget`, `ifconfig`, and `netstat`. They do not add extra
binary payload.

The default profile favors tools that work without runtime plugin trees or
shared libraries. `curl` expects the target's CA bundle at
`/etc/ssl/certs/ca-certificates.crt`; pass `--cacert`, use a private CA bundle,
or explicitly choose curl's insecure mode when that file is unavailable.
Socat's OpenSSL and readline integrations remain disabled because curl and the
standalone `openssl` utility cover TLS checks without enlarging every socat
code path. Curl uses the synchronous libc resolver. OpenSSL's thread support
is disabled on 32-bit targets to avoid relying on non-lock-free 64-bit atomic
operations in constrained ABIs; the shipped command-line tools use it from a
single thread.

Nmap is built as a compact first profile with Ncat, TLS, service detection,
OS detection, and the core databases, but without NSE/Lua, libssh2, Nping,
Zenmap, or Ndiff. Its data files are packaged under `share/nmap`; either copy
that directory to `/usr/share/nmap` on the target or invoke
`nmap --datadir /path/to/share/nmap`. Nmap and Ncat are governed by the
Nmap Public Source License rather than a standard OSI license, so review its
deployment and redistribution terms for your use case.

Rsync uses its bundled popt and zlib implementations and includes IPv4/IPv6
and local socket-pair support. Optional ACL, xattr, iconv, OpenSSL, xxHash,
zstd, and LZ4 integrations are disabled in this first portable profile. Lsof
reads the target Linux procfs and therefore reflects the target kernel's
procfs visibility and security restrictions.

Packet capture, raw probes, network changes, tracing another process, and
hardware-bus access still require the corresponding Linux capabilities,
device nodes, drivers, and security-policy permissions.

Dropbear's configure probes use `-O0` because Zig 0.16 can mis-link
Autoconf's deliberately prototype-less MIPS tests when optimized. The
generated production flags are then changed to `-Os`; shipped binaries remain
optimized, static, and stripped. Dropbear is non-PIE on MIPS because Zig
0.16's MIPS runtime cannot currently link complex static-PIE programs; all
other Dropbear targets retain static PIE.

## Supported Linux targets

The matrix covers:

- x86-64 and 32-bit x86
- AArch64
- ARMv6 hard-float and ARMv7 soft/hard-float
- 32-bit MIPS in both endian modes
- 32/64-bit PowerPC in big-endian and little-endian modes
- RISC-V 64 and s390x

See [docs/ARCHITECTURES.md](docs/ARCHITECTURES.md) for ABI details and device
selection guidance. A successful static build does not replace kernel support
for required system calls, network families, TUN, namespaces, or packet
sockets.

## Reproducibility and source trust

[`sources.lock`](sources.lock) pins every compiler and upstream source archive
by version, URL, and SHA-256. Fetches fail closed on a checksum mismatch.
Builds set a fixed `SOURCE_DATE_EPOCH`, remove debug/symbol tables with Zig's
cross-linker flags, and emit:

- `BUILDINFO` with the target and component versions
- `SHA256SUMS` for every physical payload file, including Nmap data
- the exact `sources.lock` used by the build
- `COMPONENTS.tsv` and a deterministic SPDX 2.3 SBOM
- complete upstream notices under `licenses/`

Most upstreams are fetched over HTTPS. Socat is the documented exception:
its canonical hostname does not have a matching TLS certificate, so its
release archive is fetched over HTTP and protected by the reviewed lock-file
digest. See [SECURITY.md](SECURITY.md) for the trust model and update policy.

The output contains GPL and other copyleft software. Binary bundles carry the
relevant upstream license texts and a generated `THIRD_PARTY_NOTICES.md`.
When redistributing artifacts, retain the build recipes and make corresponding
source available. `make source-package` produces the exact upstream archive
bundle used by a build. Upstream projects retain their own licenses; this
repository does not relicense their code or binaries.

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
- checks upstream releases weekly and opens a checksum-refresh PR.

Dependabot maintains Docker and GitHub Actions references. Source updates are
kept separate because generic tarball releases are not a Dependabot ecosystem;
[`scripts/update_sources.py`](scripts/update_sources.py) is the lock-file
equivalent. Update PRs are intentionally not auto-merged: CI and review of
release notes/signatures remain required. The updater explicitly dispatches
the full build for its bot-created PR branch.

See [docs/RELEASING.md](docs/RELEASING.md) for release gates, assets, and
attestation verification.

## Adding a tool or architecture

Tool recipes are isolated under `scripts/builders/`. Add a checksum-pinned
source record, implement one builder function, call it from `scripts/build.sh`,
and extend the verification expectations. Architecture definitions live in
one table, [`architectures.tsv`](architectures.tsv), and are consumed by local
builds and QEMU verification.

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
