# statics

<p align="center">
  <img src="assets/brand/statics-mark.png" width="168" alt="statics: a portable field case filled with Linux troubleshooting tools">
</p>

<p align="center">
  <strong>Bring the tools the target forgot.</strong><br>
  Reproducible, cross-architecture static Linux binaries—packed for the field.
</p>

<p align="center">
  <a href="https://github.com/0typos/statics/actions/workflows/build.yml"><img src="https://github.com/0typos/statics/actions/workflows/build.yml/badge.svg" alt="Build"></a>
  <a href="https://github.com/0typos/statics/releases"><img src="https://img.shields.io/github/v/release/0typos/statics?include_prereleases&amp;sort=semver&amp;style=flat-square&amp;color=00CFE8" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/Linux_targets-13-FFB000?style=flat-square" alt="13 Linux targets">
  <img src="https://img.shields.io/badge/libc-static_musl-FF1688?style=flat-square" alt="Statically linked with musl">
  <a href="LICENSE"><img src="https://img.shields.io/badge/build_recipes-MIT-8EA9D8?style=flat-square" alt="MIT licensed build recipes"></a>
</p>

<p align="center">
  <a href="#get-a-kit">Get a kit</a> ·
  <a href="#put-it-to-work">Use it</a> ·
  <a href="#inside-the-case">Toolkit</a> ·
  <a href="#pick-a-target">Architectures</a> ·
  <a href="#trust-what-you-carry">Trust</a> ·
  <a href="#documentation">Docs</a>
</p>

> **Broken hosts rarely have the tool you need.**

`statics` builds a portable Linux troubleshooting kit for machines where the package
manager, network or base userspace cannot help. The repository contains the recipes,
source pins, CI, verification and release machinery—not generated binaries. Build
outputs stay in local files, GitHub Actions artifacts or release assets.

Every target is compiled against musl with a pinned
[Zig](https://ziglang.org/) toolchain. Docker keeps the build environment clean; QEMU
user-mode emulation proves that non-native outputs can actually start.

## At a glance

| 🧰 Carry it | 🐧 Run it | 🔐 Trust it |
|---|---|---|
| 51 physical executables, plus BusyBox and Dropbear links | Thirteen Linux architectures from x86 to IBM Z | Pinned sources, checksums, SPDX SBOM and complete notices |
| Network, process, namespace, storage and hardware diagnosis | Static musl builds avoid a dependency on the target's libc | Deterministic archives, QEMU smoke tests and release attestations |

## Get a kit

### Release archive

Choose the archive for the target machine from the
[latest release](https://github.com/0typos/statics/releases/latest). Every archive has a
checksum beside it:

```console
arch=x86_64
sha256sum -c "statics-$arch.tar.xz.sha256"
tar -xJf "statics-$arch.tar.xz"
```

Not sure which archive fits the device? Start with the
[architecture and ABI guide](docs/ARCHITECTURES.md).

### Build one

Requirements: Git, GNU Make, Docker with Buildx, roughly 8 GB of free disk space for
the first build, and an `amd64` or `arm64` Docker host.

```console
git clone https://github.com/0typos/statics.git
cd statics
make smoke ARCH=x86_64
make build ARCH=x86_64
```

`make smoke` cross-builds in a container and runs representative commands under QEMU.
`make build` reuses those cached layers and exports the kit under `dist/x86_64/`.

```console
make list                     # show the complete target matrix
make build ARCH=mipsel        # build one target
make package ARCH=mipsel      # create dist/statics-mipsel.tar.xz
make verify ARCH=mipsel       # verify an exported build
make all                      # build every target
make sources                  # export checksum-verified source archives
make source-package           # create dist/statics-sources.tar.xz
```

`make help` is the compact command reference. Generated files live under `dist/` and
`.build/`; both are ignored by Git.

## Put it to work

Keep the directory together when you copy it to a target. Nmap data, checksums,
licenses and build metadata travel with the executables.

```console
TOOLKIT=/tmp/statics/x86_64
export PATH="$TOOLKIT:$PATH"

ip -brief address
ss -listening -numeric -tcp -udp
curl --verbose --connect-timeout 5 https://example.com/
strace -f -o /tmp/trace.log curl https://example.com/
nmap --datadir "$TOOLKIT/share/nmap" -sT -sV 192.0.2.10
```

Absolute paths are safer when the host already has commands with the same names. The
[toolkit guide](docs/TOOLKIT.md) covers feature profiles, required privileges, runtime
data and safe starting commands.

## Inside the case

The bundle contains 51 physical executables plus BusyBox and Dropbear multi-call links,
Nmap runtime data, checksums, an SPDX SBOM and upstream license texts.

| Area | Outputs | What they are for |
|---|---|---|
| Rescue userspace | `busybox`, `nc`, `netcat` | Shell recovery, basic reachability and familiar applet links |
| Remote access and transfer | `socat`, `ncat`, `rsync`, `dropbear`, `dbclient`, `dropbearkey`, `dropbearconvert`, `scp` | Relays, emergency SSH and file movement |
| Network state and control | `ip`, `ss`, `bridge`, `tc`, `wg`, `ethtool`, `nft` | Interfaces, routes, sockets, policy and NIC state |
| Discovery and packet diagnosis | `nmap`, `tcpdump`, `iperf3`, `mtr`, `mtr-packet` | Services, captures, paths and throughput |
| HTTP, TLS, DNS and data | `curl`, `openssl`, `drill`, `jq` | Protocol checks and structured output |
| Process and storage diagnosis | `strace`, `lsof`, `e2fsck`, `dumpe2fs`, `tune2fs`, `mke2fs`, `smartctl`, `nvme` | Syscalls, open files, filesystems and device health |
| Namespaces and privilege | `nsenter`, `unshare`, `lsns`, `setpriv`, `findmnt` | Enter, create, inspect and constrain Linux execution contexts |
| CAN and ISO-TP | `candump`, `cansend`, `cangen`, `canplayer`, `cansniffer`, `isotp*`, `slcand`, `canbusload` | Field and vehicle networks |
| Hardware buses | `i2cdetect`, `i2cdump`, `i2cget`, `i2cset`, `i2ctransfer`, `spi-config`, `spi-pipe` | Linux I²C and spidev diagnosis |

Convenience links expose BusyBox applets such as `ping`, `traceroute`, `nslookup`,
`arping`, `wget`, `ifconfig` and `netstat` without adding extra binary payload.

The portable default deliberately leaves some integrations out. Keep Nmap's packaged
`share/nmap/` beside the executable, provide curl a trusted CA bundle when the target
lacks one, and do not expect rsync to preserve ACLs or extended attributes. Nmap and
Ncat use the Nmap Public Source License; review their packaged terms before deployment
or redistribution.

## Pick a target

The matrix covers:

| family | targets |
|---|---|
| x86 | `x86_64`, `i686` |
| ARM | `aarch64`, `armv6-hardfloat`, `armv7-hardfloat`, `armv7-softfloat` |
| MIPS | `mips`, `mipsel` |
| PowerPC | `powerpc`, `powerpc64`, `powerpc64le` |
| Other | `riscv64`, `s390x` |

A successful static build removes the installed-libc dependency. It does not provide
missing syscalls, network families, TUN support, namespaces, packet sockets or device
drivers. Check the target kernel and ABI before heading into the field.

Static linking does not grant permissions. Packet capture, raw probes, network changes,
process tracing and hardware-bus access still require the corresponding Linux
capabilities, device nodes and security policy.

## Trust what you carry

[`sources.lock`](sources.lock) pins every compiler and upstream source archive by
version, URL and SHA-256. Fetches fail closed on a checksum mismatch. Builds set a fixed
`SOURCE_DATE_EPOCH`, strip debug and symbol tables with Zig's cross-linker flags, and
emit:

- `BUILDINFO` with the target and component versions
- `SHA256SUMS` for every executable payload and Nmap runtime file
- the exact `sources.lock` used for the build
- `COMPONENTS.tsv` and a deterministic SPDX 2.3 SBOM
- complete upstream notices under `licenses/`
- the build-recipe MIT license as `BUILD_RECIPES_LICENSE`

Most upstreams are fetched over HTTPS. Socat is the documented exception: its canonical
hostname has no matching TLS certificate, so the archive is fetched over HTTP and
protected by the reviewed lock-file digest. [Security](SECURITY.md) documents that trust
boundary and the update policy.

The output includes GPL and other copyleft software. `make source-package` produces the
exact upstream archive set used by a build so corresponding source can travel with the
binary kit.

## Automation

Published binaries are rebuilt automatically every month. The scheduled workflow
repins every component, rebuilds all thirteen architectures and publishes only after
every verification gate passes. When no input changed, it skips the release rather than
republishing the same bits.

Each candidate is validated, cross-built, verified as statically linked and smoke-run
under QEMU. CI also rebuilds x86-64 twice and compares the complete output, publishes
checksums, SBOMs, notices and matching sources, and attaches GitHub/Sigstore provenance
and SBOM attestations. A weekly build catches toolchain regressions; a separate updater
opens reviewed checksum-refresh PRs.

Monthly repinning is intentionally unattended and never writes to `main`. The
[release guide](docs/RELEASING.md) explains every gate, retention, retry and attestation
rule, including how to disable the schedule.

## Documentation

| Build | Operate | Trust | Extend |
|---|---|---|---|
| [Building](docs/BUILDING.md)<br>[Architectures](docs/ARCHITECTURES.md)<br>[Troubleshooting](docs/TROUBLESHOOTING.md) | [Toolkit](docs/TOOLKIT.md)<br>[Command examples](docs/TOOLKIT.md#common-network-checks) | [Security](SECURITY.md)<br>[Releasing](docs/RELEASING.md)<br>[Source pins](sources.lock) | [Contributing](CONTRIBUTING.md)<br>[Roadmap](docs/ROADMAP.md)<br>[Components](components.tsv) |

## Add to the kit

Tool recipes are isolated under `scripts/builders/`; architecture definitions live in
[`architectures.tsv`](architectures.tsv). The [contribution guide](CONTRIBUTING.md) has
the checklists for adding either without weakening source, license, static-link or
verification coverage.

Linux is the current contract. Darwin and Windows remain separate future target
families because their libc, executable formats, networking APIs and validation
environments differ substantially.

## Licensing

Repository-authored build recipes, scripts, configuration and documentation are
licensed under the [MIT License](LICENSE), unless a file says otherwise. That license
does not replace or override the licenses of the utilities, libraries or source archives
the project builds.

[`components.tsv`](components.tsv) indexes the upstream terms. Every binary bundle
includes `THIRD_PARTY_NOTICES.md` and the relevant texts under `licenses/<source>/`.
Redistributors remain responsible for applicable corresponding-source obligations and
Nmap's NPSL terms.

## Prior art

`statics` draws useful ideas—and avoids the checked-in artifact model—from:

- [perryflynn/static-binaries](https://github.com/perryflynn/static-binaries)
- [andrew-d/static-binaries](https://github.com/andrew-d/static-binaries)
- [polaco1782/linux-static-binaries](https://github.com/polaco1782/linux-static-binaries)
- [ryanwoodsmall/static-binaries](https://github.com/ryanwoodsmall/static-binaries)
