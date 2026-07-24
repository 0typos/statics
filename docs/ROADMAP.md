# Tool roadmap

The current bundle covers rescue userspace, relays and remote access, network
configuration, socket and packet inspection, HTTP/TLS/DNS checks, throughput
and path diagnosis, syscall tracing, JSON processing, and common IoT field
buses.

## Included now

| Area | Tools |
| --- | --- |
| Network control | `ip`, `ss`, `bridge`, `tc`, `wg`, `ethtool` |
| Packet, path, and throughput | `tcpdump`, `mtr`, `iperf3` |
| Application protocols and data | `curl`, `openssl`, `drill`, `jq` |
| Process diagnosis | `strace` |
| Embedded buses | selected `can-utils`, `i2c-tools`, and `spi-tools` programs |

## Candidates for the next expansion

| Priority | Tool | Diagnostic value | Build considerations |
| --- | --- | --- | --- |
| 1 | `nmap`/`ncat` | Discovery, service probing, and richer netcat behavior | Large feature/data-file surface; define a minimal profile |
| 1 | `rsync` | Recovery transfer and remote comparison | Compression and crypto dependency choices |
| 1 | `lsof` | Process/file/socket correlation | Portability and procfs assumptions |
| 2 | `smartctl`, `nvme-cli` | Storage health and device diagnosis | Hardware/ioctl and database considerations |
| 2 | `usbutils` | USB topology, descriptors, and device identification | Decide whether and how to package the USB ID database |
| 2 | `fio` | Storage and I/O characterization | Larger binary and workload safety considerations |
| 3 | `stress-ng` | CPU, memory, scheduler, and system stress | Large surface and intentionally disruptive workloads |
| 3 | `nft` | Inspect and repair modern packet-filter rules | libnftables and JSON/parser dependency surface |
| 3 | `conntrack` | Stateful firewall and NAT diagnosis | Netfilter-specific libraries and kernel support |

Possible profiles can add TLS-enabled socat, compressed Dropbear sessions,
interactive/curses mtr, and broader protocol support in curl without forcing
those dependencies into the compact default bundle.

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

## Platform expansion

Linux remains phase one.

Darwin should use Mach-O targets and native/macOS CI validation. Fully static
system binaries are generally not the same compatibility proposition as
musl/Linux, so “portable, minimally dependent” may be the more honest goal.

Windows should use PE/COFF targets, distinguish console utilities from
drivers/services, and test on Windows runners. Winsock, privilege, certificate
store, and packet-capture behavior need platform-specific recipes rather than
conditional branches inside the Linux builders.
