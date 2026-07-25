# Tool roadmap

The current bundle covers rescue userspace, relays and remote access, network
configuration, socket and packet inspection, HTTP/TLS/DNS checks, throughput
and path diagnosis, syscall tracing, JSON processing, and common IoT field
buses.

This page records candidates, not commitments. The executable contract is in
the [toolkit guide](TOOLKIT.md), and implementation proposals should follow
the [contribution checklist](../CONTRIBUTING.md).

## Included now

| Area | Tools |
| --- | --- |
| Network control | `ip`, `ss`, `bridge`, `tc`, `wg`, `ethtool` |
| Packet, path, and throughput | `tcpdump`, `mtr`, `iperf3` |
| Application protocols and data | `curl`, `openssl`, `drill`, `jq` |
| Discovery and transfer | `nmap`, `ncat`, `rsync` |
| Process diagnosis | `strace`, `lsof` |
| Namespaces and privilege | `nsenter`, `unshare`, `lsns`, `setpriv`, `findmnt` |
| Embedded buses | selected `can-utils`, `i2c-tools`, and `spi-tools` programs |

## Candidates for the next expansion

Priority 1 means “evaluate next,” priority 2 is valuable but dependency-heavy,
and priority 3 is specialized, large, interactive, or intentionally
disruptive.

| Priority | Tool | Diagnostic value | Build considerations |
| --- | --- | --- | --- |
| 1 | `smartctl`, `nvme-cli` | Storage health and device diagnosis | Hardware ioctls, database packaging, and device permissions |
| 1 | `usbutils`, `pciutils` | Bus topology, descriptors, and device identification | Package and update hardware ID databases explicitly |
| 1 | `mmc-utils` | eMMC/SD health, EXT_CSD, and device configuration | Write operations can be destructive; needs real-device tests |
| 2 | `iw` | Wi-Fi link, station, scan, and regulatory diagnosis | libnl/static netlink dependencies and wireless privileges |
| 2 | `nft` | Inspect and repair modern packet-filter rules | libnftables and JSON/parser dependency surface |
| 2 | `conntrack` | Stateful firewall and NAT diagnosis | Netfilter-specific libraries and kernel support |
| 2 | `bpftool` | Inspect BPF programs, maps, links, and features | Large kernel-header/libbpf surface and strong kernel coupling |
| 2 | `fio` | Storage and I/O characterization | Larger binary, workload safety, and reproducibility considerations |
| 3 | `iftop`, `nethogs` | Interactive per-flow or per-process traffic visibility | curses, procfs, capture privileges, and non-interactive testability |
| 3 | `stress-ng` | CPU, memory, scheduler, and system stress | Large surface and intentionally disruptive workloads |

Also consider focused variants instead of new binaries: TLS-enabled socat,
compressed Dropbear sessions, interactive/curses mtr, broader curl protocols,
Nmap NSE/Lua, and rsync ACL/xattr/compression/checksum integrations. Profiles
need distinct names and verification so the compact default remains
predictable.

Before adding a standalone tool, check BusyBox and the existing specialist
utilities. For example, `drill` already covers DNS queries, `ss` covers most
socket-listing needs, and `ip` covers modern address/route/link inspection.

BusyBox already provides useful versions of `ping`, `traceroute`, `arping`,
`nslookup`, `wget`, `telnet`, `ifconfig`, `route`, `netstat`, `dmesg`, `hexdump`,
`sha256sum`, and many ordinary shell tools. A standalone replacement should
only be added when its missing functionality justifies the extra payload.

## Selection criteria

A candidate should be:

- actively maintained and releasable from a stable, checksumable source;
- useful during an outage or on a minimal/rescue system;
- cross-compilable without executing target code during the build;
- functional without an unbundled runtime database, plugin tree, or shared
  library—or package those resources explicitly;
- reasonably sized for constrained devices;
- testable without pretending QEMU can validate privileged hardware behavior.

For priority 1 candidates, a proposal should additionally identify an
upstream source/update mechanism, static dependency plan, license expression,
runtime data files, safe smoke command, approximate size, and at least one
real-device validation path.

## Platform expansion

Linux remains phase one.

ARMv5 soft-float is deferred from the first release. The currently pinned
Zig compiler runtime requires atomic operations that ARMv5 cannot provide
directly. Revisit the target when Zig supplies a supported fallback or when a
separately maintained musl toolchain can be justified and tested on real
ARMv5 Linux hardware.

MIPS64 big- and little-endian ABIs are also deferred. The currently pinned
Zig/LLD toolchain discards OpenSSL CLI sections incorrectly with this
repository's static, section-garbage-collected link profile. The first release
retains both big- and little-endian MIPS32 targets.

LoongArch64 is deferred until the older Autotools projects in the dependency
chain can be updated without carrying generated `config.sub` replacements in
the first release.

Darwin should use Mach-O targets and native/macOS CI validation. Fully static
system binaries are generally not the same compatibility proposition as
musl/Linux, so “portable, minimally dependent” may be the more honest goal.

Windows should use PE/COFF targets, distinguish console utilities from
drivers/services, and test on Windows runners. Winsock, privilege, certificate
store, and packet-capture behavior need platform-specific recipes rather than
conditional branches inside the Linux builders.
