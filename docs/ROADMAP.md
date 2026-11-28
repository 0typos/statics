# Tool roadmap

The current bundle covers rescue userspace, relays and remote access, network
configuration, socket and packet inspection, HTTP/TLS/DNS checks, throughput
and path diagnosis, payload search, crafted probes and capture replay, live
bandwidth by host and process, LLDP neighbors, firewall policy (nftables and
legacy x_tables), IP sets, and connection tracking, Wi-Fi, syscall
tracing, remote debugging, serial consoles, filesystem, block-device, and raw
flash diagnosis, kernel modules, kexec, and eBPF inspection, BMC management over IPMI, compression, archives, and
buffered pipe transfer, JSON processing, common IoT field buses, persistent
terminal sessions and bash, TLS wrapping, OpenVPN, SOCKS5 and HTTP proxies,
DHCP, DNS, and TFTP for netboot, serial ports shared over the network,
TLS server auditing, SFTP and SCP with curl, SMB and NFS mounts, partition
imaging and multicast, fast checksums, SQLite databases, JavaScript and Lua
scripts, GNU make, and an interactive process view. The optional extra archive adds
object-storage and SFTP sync, directory mirroring, resumable segmented
downloads, parity repair, code-phrase file transfer, container runtime
inspection, a reverse proxy and web server, YAML processing, file encryption,
Python, and a C compiler with GNU binutils.

This page records candidates, not commitments. The executable contract is in
the [toolkit guide](TOOLKIT.md), and implementation proposals should follow
the [contribution checklist](../CONTRIBUTING.md).

## Included now

| Area | Tools |
| --- | --- |
| Network control | `ip`, `ss`, `bridge`, `tc`, `nstat`, `devlink`, `rdma`, `wg`, `ethtool`, `nft`, `conntrack`, `ipset`, `iw` |
| Legacy firewalls | `iptables-legacy`, `ip6tables-legacy`, `ebtables-legacy`, `arptables-legacy` |
| Reachability and path | `ping`, `arping`, `tracepath`, `traceroute`, `ndisc6`, `rdisc6`, `rltraceroute6`, `tcptraceroute6`, `mtr` |
| Packet and throughput | `tcpdump`, `ngrep`, `dhcpdump`, `hping3`, `tcpreplay`, `tcpprep`, `tcprewrite`, `iftop`, `nethogs`, `iperf3` |
| Link-layer discovery | `lldpd`, `lldpcli` |
| Application protocols and data | `curl`, `openssl`, `drill`, `jq` |
| Discovery and transfer | `nmap`, `ncat`, `rsync`, `sftp-server`; `lftp` and `aria2c` in the extra archive |
| Network shares | `mount.cifs`, `mount.nfs`, `showmount` |
| Imaging and multicast | partclone (ext, FAT, `dd`), `udp-sender`, `udp-receiver` |
| Checksums and parity | `xxhsum`; `par2` in the extra archive |
| Compression and archives | `zstd`, `xz`, `bzip2`, `pigz`, `bsdtar`, `bsdcpio` |
| Pipe transfer | `pv`, `mbuffer` |
| Tunnels and VPN | `tunpipe`, `pppd`; `openvpn` in the extra archive |
| TLS wrapping and proxies | `microsocks`, `tinyproxy`; `stunnel` in the extra archive |
| DHCP, DNS, and netboot | `dnsmasq` |
| Sessions and shells | `tmux`, `bash` |
| Scripting, data, and builds | `sqlite3`, `qjs`, `lua`, `make` |
| TLS auditing | `testssl.sh` |
| Serial console and transfer | `picocom`, `sz`, `rz`, `ser2net` |
| Process diagnosis | `htop`, `strace`, `lsof`, `gdbserver` |
| Filesystems and storage | `lsblk`, `blkid`, `sfdisk`, `losetup`, `mount`, `umount`, `e2fsck`, `dumpe2fs`, `tune2fs`, `mke2fs`, `smartctl`, `nvme` |
| Kernel log | `dmesg` |
| Kernel modules, boot, and BPF | `kmod` (`modinfo`, `lsmod`, `insmod`, `rmmod`, `modprobe`, `depmod`), `kexec`, `bpftool` |
| Raw flash and UBI | selected `mtd-utils` programs |
| Out-of-band management | `ipmitool` |
| Namespaces and privilege | `nsenter`, `unshare`, `lsns`, `setpriv`, `findmnt` |
| Embedded buses | selected `can-utils`, `i2c-tools`, and `spi-tools` programs |

The extra archive adds `stunnel`, `openvpn`, `lftp`, and `aria2c` (each with
its own OpenSSL), `par2`, `python3`, and nine binutils programs on every target, `tcc` on six, and `rclone` (trimmed), `croc`, `crictl`, `ctr`, `caddy`, `yq`, `age`, and `age-keygen` where Go
runs.
Further rclone backends and commands are requests against its trimmed main
rather than new tools; see the [toolkit guide](TOOLKIT.md#rclone-trimmed).

## Candidates for the next expansion

Priority 1 means “evaluate next,” priority 2 is valuable but dependency-heavy,
and priority 3 is specialized, large, interactive, or intentionally
disruptive.

| Priority | Tool | Diagnostic value | Build considerations |
| --- | --- | --- | --- |
| 1 | `usbutils`, `pciutils` | Bus topology, descriptors, and device identification | Package and update hardware ID databases explicitly |
| 1 | `mmc-utils` | eMMC/SD health, EXT_CSD, and device configuration | Write operations can be destructive; needs real-device tests |
| 2 | `fio` | Storage and I/O characterization | Larger binary, workload safety, and reproducibility considerations |
| 2 | partclone btrfs, XFS, and NTFS | Image the filesystems of most Linux servers and Windows disks | btrfs alone is about 280 KB of xz; XFS needs liburcu, NTFS ntfs-3g; probably the extra archive |
| 3 | `stress-ng` | CPU, memory, scheduler, and system stress | Large surface and intentionally disruptive workloads |
| 3 | `tcpflow` | Reassemble TCP streams into files | Needs Boost (C++ headers), a large build dependency for one tool |
| 3 | `fzf` | Fuzzy search over any list | Go, but its unaligned 64-bit loads fault on `mips` and `mipsel` (SIGBUS under QEMU 10); needs an upstream fix or a patch |
| 3 | `b3sum` | BLAKE3 checksums | Upstream's only CLI is Rust; a C `b3sum` would be new code over the C library |
| 3 | `nghttp`, `h2load` | HTTP/2 client and load generator | C++23 with libev, c-ares, and zlib, and two more static copies of OpenSSL: about 3 MB of archive; libnghttp2 in `curl` is the cheap alternative |

Also consider focused variants instead of new binaries:
HTTP/2 in `curl` (libnghttp2, C only), bash 5.3 (each official patch pinned
separately), OpenVPN data channel offload (libnl is already built for `iw`),
compressed Dropbear sessions, interactive/curses mtr (the bundle now builds
ncurses for iftop and nethogs), broader curl protocols, Nmap NSE/Lua, Nping
(about 410 KB, mostly another copy of libcrypto), and rsync
ACL/xattr/compression/checksum integrations. Profiles
need distinct names and verification so the compact default remains
predictable.

Before adding a standalone tool, check BusyBox and the existing specialist
utilities. For example, `drill` already covers DNS queries, `ss` covers most
socket-listing needs, and `ip` covers modern address/route/link inspection.

BusyBox already provides useful versions of `nslookup`, `wget`, `telnet`,
`ifconfig`, `route`, `netstat`, `dmesg`, `hexdump`, `sha256sum`, and many ordinary
shell tools. A standalone replacement should only be added when its missing
functionality justifies the extra payload, as iputils' `ping`, `arping`, and
`tracepath` and the modern `traceroute` (TCP and UDP modes, unprivileged
ICMP sockets, path MTU) now replace BusyBox's applets.

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
