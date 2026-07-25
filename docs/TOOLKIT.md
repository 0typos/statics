# Toolkit guide

The default bundle is a compact Linux troubleshooting kit: 44 physical
executables, BusyBox applet links, Dropbear multi-call links, Nmap runtime
data, license texts, checksums, and build metadata. Static linking removes the
dependency on a target's installed libc; it does not replace kernel features,
drivers, device nodes, certificate stores, permissions, or runtime databases.

Use these tools only on systems and networks where you are authorized.

## Start a session

Assume the bundle has been copied to `/tmp/statics` on the target:

```console
TOOLKIT=/tmp/statics
export PATH="$TOOLKIT:$PATH"
```

Running with absolute paths is safer when the target already has commands
with the same names. Preserve the whole directory when moving the kit so that
Nmap data, notices, and licenses remain available.

## Tool inventory

| Area | Executables and links | Primary use |
| --- | --- | --- |
| Rescue userspace | `busybox`; `ping`, `ping6`, `traceroute`, `traceroute6`, `nslookup`, `wget`, `telnet`, `arp`, `arping`, `route`, `ifconfig`, `netstat`, `nc`, `netcat` | Shell recovery, basic reachability, and legacy network inspection |
| Relays and remote access | `socat`, `ncat`, `dropbearmulti`; `dropbear`, `dbclient`, `dropbearkey`, `dropbearconvert`, `scp` | TCP/UDP relays, port checks, emergency SSH, and file copy |
| Network control | `ip`, `ss`, `bridge`, `tc`, `wg`, `ethtool` | Addresses, routes, sockets, links, traffic control, WireGuard, and NIC state |
| Discovery and packet diagnosis | `nmap`, `tcpdump`, `mtr`, `mtr-packet`, `iperf3` | Host/service discovery, capture, path analysis, and throughput |
| Protocol and data checks | `curl`, `openssl`, `drill`, `jq`, `rsync` | HTTP, TLS, DNS, structured output, and efficient file transfer |
| Process diagnosis | `strace`, `lsof` | System-call tracing and process/file/socket correlation |
| Namespaces and privilege | `nsenter`, `unshare`, `lsns`, `setpriv`, `findmnt` | Enter, create, enumerate, constrain, and inspect namespace state |
| CAN and ISO-TP | `candump`, `cansend`, `cangen`, `canplayer`, `cansniffer`, `isotpdump`, `isotprecv`, `isotpsend`, `slcand`, `canbusload` | SocketCAN and ISO-TP field diagnosis |
| Hardware buses | `i2cdetect`, `i2cdump`, `i2cget`, `i2cset`, `i2ctransfer`, `spi-config`, `spi-pipe` | Linux I²C and spidev diagnosis |

The BusyBox and Dropbear entries after the semicolon are symbolic links to
their multi-call binary; they do not add separate binary payloads.

## License boundary

`BUILD_RECIPES_LICENSE` contains the MIT license for this repository's
original build machinery. It is not a blanket license for the toolkit.
Every bundled project retains its own license, indexed in `COMPONENTS.tsv`
and reproduced under `licenses/<source>/`. Read `THIRD_PARTY_NOTICES.md`
before redistributing a bundle; Nmap and Ncat have particularly distinct NPSL
terms.

## Linux namespaces

`setns(2)` is the kernel system call for joining an existing namespace. Linux
does not provide a separate canonical `setns` command; util-linux `nsenter`
is the standard maintained CLI around that syscall.

Enumerate namespaces and inspect the current mount view:

```console
lsns
findmnt --kernel
findmnt --target /tmp
```

Enter only a process's network namespace and inspect it with the bundled
iproute2 tools:

```console
TARGET_PID=1234
nsenter --target "$TARGET_PID" --net ip -brief address
nsenter --target "$TARGET_PID" --net ss -listening -numeric -tcp -udp
```

Enter the common namespaces of a process and start its system shell:

```console
nsenter --target "$TARGET_PID" --mount --uts --ipc --net --pid -- /bin/sh
```

Joining the mount namespace changes path resolution. A toolkit stored only in
the caller's mount namespace may disappear after `--mount`; copy it somewhere
visible in both views or use commands available in the target root.

Create an isolated user, mount, and PID namespace when the kernel permits
unprivileged user namespaces:

```console
unshare --user --map-root-user --mount --pid --fork --mount-proc /bin/sh
```

Inspect the current privilege state or constrain a child command:

```console
setpriv --dump
setpriv --no-new-privs --bounding-set=-all \
    --inh-caps=-all --ambient-caps=-all /bin/sh
```

The second command changes only the child execution context, but capability
bounding-set removal is irreversible for that process tree. Test privilege
profiles against the intended workload before operational use.

Namespace entry normally requires `CAP_SYS_ADMIN` in the user namespace that
owns the target namespace. User-namespace creation can be disabled by the
kernel or policy. PID namespace entry affects subsequently created children,
not the already-running `nsenter` process. `lsns` and `findmnt` depend on
procfs visibility and can show partial information across containers or
restricted procfs mounts.

## Common network checks

Inspect interfaces, routes, neighbors, and listening sockets:

```console
ip -brief address
ip route show
ip neighbor show
ss -listening -numeric -tcp -udp
ethtool eth0
```

Check name resolution, HTTP, TLS, and a TCP port:

```console
drill example.com
curl --verbose --connect-timeout 5 https://example.com/
openssl s_client -connect example.com:443 -servername example.com </dev/null
ncat --verbose --wait 5 example.com 443
```

Check reachability and path behavior:

```console
ping -c 4 192.0.2.1
traceroute 192.0.2.1
mtr --report --report-cycles 5 192.0.2.1
```

Run a conservative TCP connect scan against an authorized host:

```console
nmap --datadir "$TOOLKIT/share/nmap" -sT -sV 192.0.2.10
```

Capture traffic or correlate a port with a process:

```console
tcpdump -n -i any -c 100
lsof -nP -i
lsof -nP -iTCP:443
```

Trace a command that is failing:

```console
strace -f -o /tmp/trace.log curl --connect-timeout 5 https://example.com/
```

Measure throughput only when an `iperf3` peer has been intentionally started:

```console
iperf3 --client 192.0.2.20 --time 10
```

Synchronize a diagnostic directory:

```console
rsync --archive --verbose -e "$TOOLKIT/dbclient" \
    /var/log/ operator@192.0.2.20:incident-logs/
```

Rsync must be available at both ends of a remote transfer. The explicit
`dbclient` remote shell avoids assuming that a separate `ssh` executable is
installed on the minimal target.

These are starting points, not permission bypasses. Raw sockets, packet
capture, interface changes, another process's state, and device access often
need root or narrowly assigned Linux capabilities.

## Default profile and intentional omissions

The recipes favor broad static portability over enabling every optional
feature.

### Nmap and Ncat

Nmap includes Ncat, TLS, service detection, OS detection, libpcap, and the
core databases. NSE/Lua, libssh2, Nping, Zenmap, and Ndiff are disabled.
Runtime data is under `share/nmap`; either pass:

```console
nmap --datadir "$TOOLKIT/share/nmap" TARGET
```

or install that directory at `/usr/share/nmap` on the destination.

Nmap and Ncat use the Nmap Public Source License. Review the packaged
`licenses/nmap/LICENSE` and the deployment/redistribution terms for the
intended use.

### Curl and OpenSSL

Curl uses the synchronous libc resolver and the standalone OpenSSL build. It
expects a CA bundle at `/etc/ssl/certs/ca-certificates.crt`. When a target
lacks that file, supply a trusted bundle explicitly:

```console
curl --cacert /path/to/ca-bundle.pem https://example.com/
```

Use `--insecure` only as a deliberate diagnostic choice; it disables server
certificate verification.

OpenSSL thread support is disabled on 32-bit targets to avoid non-lock-free
64-bit atomic requirements in constrained ABIs. The shipped command-line
utilities are used single-threaded.

### Socat and Dropbear

Socat is built without OpenSSL and readline. Use `ncat`, `curl`, or the
standalone `openssl` command for TLS-oriented checks.

Dropbear disables zlib. Its links include server, client, key, conversion, and
SCP commands. Starting an emergency SSH server expands the target's attack
surface; use explicit host keys, authentication policy, bind addresses, and a
short lifetime appropriate to the incident.

Dropbear remains optimized and stripped. It is non-PIE on MIPS because the
pinned Zig MIPS runtime cannot currently link this complex program as static
PIE; other Dropbear targets retain static PIE.

### Rsync

Rsync includes IPv4/IPv6, local socket-pair support, and bundled popt and
zlib. ACL, xattr, iconv, OpenSSL, xxHash, zstd, and LZ4 integrations are
disabled. Preserve those limitations when designing backup or migration
workflows: a successful copy does not imply ACL or extended-attribute
preservation.

### Lsof

Lsof reads Linux procfs. Results depend on procfs being mounted and on its
`hidepid` setting, namespaces, user IDs, Linux security modules, and other
kernel restrictions. An empty or partial listing does not necessarily mean
the resource is unused.

### MTR and hardware tools

MTR is built without its curses interface; use report mode. CAN, ISO-TP, I²C,
and SPI commands require the target kernel drivers and relevant network
interfaces or device nodes. Write-oriented bus commands can alter hardware
state—inspect the device documentation first.

### Util-linux namespace profile

The util-linux build contains only `nsenter`, `unshare`, `lsns`, `setpriv`,
and `findmnt`, with static libblkid, libmount, libsmartcols, and libcap-ng as
needed. NLS, udev, SELinux, systemd, libmagic, cryptsetup, ncurses, readline,
and Python integrations are disabled. BusyBox already supplies complementary
applets such as `chroot`, `mount`, `umount`, and `pivot_root`.

## Privilege guide

Exact rules vary by kernel and security policy, but these are common:

| Operation | Typical requirement |
| --- | --- |
| TCP connect checks, DNS, HTTP, TLS | Unprivileged network access |
| ICMP/raw probes, some Nmap scan modes, packet capture | root or capabilities such as `CAP_NET_RAW` |
| Address, route, link, WireGuard, bridge, or traffic-control changes | root or `CAP_NET_ADMIN` |
| Trace or inspect another user's process | root, ptrace permission, and compatible LSM policy |
| Enter another process's namespaces | commonly root or `CAP_SYS_ADMIN` in the owning user namespace |
| Create user/network/mount/PID namespaces | kernel namespace support plus the applicable sysctl, LSM, seccomp, and capability policy |
| Read I²C/SPI devices or CAN interfaces | suitable device/interface permissions and drivers |
| Start a listener on a privileged port | root or `CAP_NET_BIND_SERVICE` |

Do not add capabilities to the whole toolkit directory. If policy permits,
grant the minimum capability to the minimum executable and remove it after
the diagnostic session.

For build failures and runtime error messages, see
[troubleshooting](TROUBLESHOOTING.md).
