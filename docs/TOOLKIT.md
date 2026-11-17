# Toolkit guide

The default bundle is a compact Linux troubleshooting kit: 88 physical
executables (87 on `powerpc` and `powerpc64`, which have no Go tools),
BusyBox applet links, Dropbear multi-call links, decompressor links, Nmap runtime
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
| Relays and remote access | `socat`, `ncat`, `pppd`, `tunpipe-standalone`, `sftp-server`, `dropbearmulti`; `dropbear`, `dbclient`, `dropbearkey`, `dropbearconvert`, `scp`, `tunpipe` | TCP/UDP/TLS relays, port checks, emergency SSH, SFTP and SCP file copy, and IP tunnels over SSH |
| Network control | `ip`, `ss`, `bridge`, `tc`, `wg`, `wireguard-go`, `ethtool`, `nft`, `conntrack`, `iw` | Addresses, routes, sockets, links, traffic control, WireGuard (with or without the kernel module), firewall policy, connection tracking, Wi-Fi, and NIC state |
| Discovery and packet diagnosis | `nmap`, `tcpdump`, `mtr`, `mtr-packet`, `iperf3` | Host/service discovery, capture, path analysis, and throughput |
| Protocol and data checks | `curl`, `openssl`, `drill`, `jq`, `rsync` | HTTP, TLS, DNS, structured output, and efficient file transfer |
| Compression and archives | `zstd`, `xz`, `bzip2`, `pigz`, `bsdtar`, `bsdcpio`; `unzstd`, `zstdcat`, `unxz`, `xzcat`, `bunzip2`, `bzcat`, `unpigz` | Stream compression, and tar, cpio, zip, 7z, ISO 9660, and ar archives; RAR read-only |
| Pipe transfer | `pv`, `mbuffer` | Progress and rate limits on a pipe, and a large buffer that keeps a stream moving across stalls |
| Serial console and transfer | `picocom`, `sz`, `rz` | Serial terminal sessions and XMODEM/YMODEM/ZMODEM file transfer |
| Process diagnosis | `strace`, `lsof`, `gdbserver` | System-call tracing, process/file/socket correlation, and remote debugging with a host GDB |
| Filesystems and storage | `lsblk`, `blkid`, `sfdisk`, `losetup`, `mount`, `umount`, `e2fsck`, `dumpe2fs`, `tune2fs`, `mke2fs`; `fsck.ext2`, `fsck.ext3`, `fsck.ext4`, `mkfs.ext4`; `smartctl`, `nvme` | Block-device and partition inventory, loop devices, mounts, ext filesystem inspection and repair, drive health, and NVMe diagnosis |
| Kernel log | `dmesg` | Kernel ring buffer with levels, facilities, and readable timestamps |
| Raw flash and UBI | `flash_erase`, `flashcp`, `nanddump`, `nandwrite`, `mtdinfo`, `ubiattach`, `ubidetach`, `ubinfo`, `ubimkvol`, `ubirmvol`, `ubiupdatevol` | MTD NOR/NAND inspection, backup, and reflashing; UBI attach and volume management |
| Out-of-band management | `ipmitool` | BMC sensors, event log, power control, and serial-over-LAN through the local IPMI driver or the network |
| Namespaces and privilege | `nsenter`, `unshare`, `lsns`, `setpriv`, `findmnt` | Enter, create, enumerate, constrain, and inspect namespace state |
| CAN and ISO-TP | `candump`, `cansend`, `cangen`, `canplayer`, `cansniffer`, `isotpdump`, `isotprecv`, `isotpsend`, `slcand`, `canbusload` | SocketCAN and ISO-TP field diagnosis |
| Hardware buses | `i2cdetect`, `i2cdump`, `i2cget`, `i2cset`, `i2ctransfer`, `spi-config`, `spi-pipe` | Linux I²C and spidev diagnosis |

Entries after a semicolon are symbolic links to a multi-call binary (BusyBox,
Dropbear, e2fsck, mke2fs) or to a compressor that picks its mode from its
name; they do not add separate binary payloads.

Four larger Go tools ship separately in `statics-extra-<arch>.tar.xz`, for
every architecture with Go (not `powerpc` or `powerpc64`). It extracts to
`<arch>-extra/` with its own notices, SBOM, and checksums; see
[the extra archive](#extra-archive-rclone-croc-crictl-and-ctr).

| Area | Executables | Primary use |
| --- | --- | --- |
| File transfer and sync | `rclone`, `croc` | Copy and sync with S3, SFTP, WebDAV, and HTTP; hand a file to another machine with a one-time code |
| Container runtimes | `crictl`, `ctr` | Inspect pods, containers, images, logs, and snapshots through the CRI and containerd sockets |

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

Inspect firewall state without changing it:

```console
nft list ruleset
```

Inventory storage and inspect an ext filesystem without writing to it:

```console
smartctl --scan-open
nvme list
dumpe2fs -h /dev/DEVICE
e2fsck -n /dev/DEVICE
```

Block-device names are deliberately placeholders. Confirm the device and mount state
before running any filesystem, SMART, or NVMe command.

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

## Moving data

Stream a directory to another host over SSH, compressed, with a progress
meter; `zstd` and `bsdtar` (or a `tar` with zstd support) must be on the far
end's `PATH`:

```console
bsdtar -cf - -C /var log | zstd -T0 -3 | pv |
    dbclient operator@192.0.2.20 'zstd -d | bsdtar -xf - -C /srv/incident'
```

Pull a disk image the other way, compressing on the device so the slow link
carries less (reading the device needs root on it):

```console
dbclient root@192.0.2.30 'zstd -T0 -3 </dev/mmcblk0' | pv | zstd -d >device.img
```

On a trusted network without SSH, `mbuffer` on both ends keeps the pipe
full while the disk or the network briefly stalls. Start the receiver first;
nothing here is encrypted or authenticated:

```console
# Receiver, 192.0.2.20
ncat --listen --recv-only 9000 | mbuffer -q -m 256M | zstd -d | bsdtar -xf - -C /srv/restore
# Sender
bsdtar -cf - -C /srv data | zstd -T0 | mbuffer -q -m 256M | ncat --send-only 192.0.2.20 9000
```

`mbuffer -I 9000` and `mbuffer -O 192.0.2.20:9000` do the same without
`ncat`. Use `pv -L 5m` to cap a transfer at 5 MiB/s on a shared link, and
`pv -s SIZE` for a percentage and ETA when the size is known.

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

Socat is built with OpenSSL and without readline. It shares the bundle's
pinned static OpenSSL, so it can open, terminate, and relay TLS in addition to
plaintext streams. To front a plaintext service with TLS:

```sh
socat OPENSSL-LISTEN:8443,reuseaddr,fork,cert=server.pem,verify=0 \
    TCP:127.0.0.1:8080
```

`ncat --ssl`, `curl`, and the standalone `openssl` command remain available for
client-side TLS checks.

Dropbear disables zlib. Its links include server, client, key, conversion, and
SCP commands.

`sftp-server` is OpenSSH's SFTP server, built alone (no `ssh`, `sshd`,
OpenSSL, or zlib). The `dropbear` server runs the `sftp-server` that sits
beside `dropbearmulti`, so `sftp` and the default mode of OpenSSH 9 and later
`scp`, which uses SFTP, work against the bundle wherever it is unpacked.
Keep the two files together. Without one there, Dropbear falls back to its
compile-time `/usr/libexec/sftp-server`. Dropbear passes the path to the
login shell unquoted, so a bundle path containing characters other than
letters, digits, and `/._+-` also falls back. The server checks for the
file as root, so a user who cannot reach the bundle directory (for example
`/root/statics` with mode 0700) gets a failed SFTP session, not the
fallback; unpack the bundle somewhere every SFTP user can read.
Legacy `scp -O` instead runs `scp` on the server through the login shell's
`PATH`, which normally does not include the bundle.

```console
dropbear -R -p 2222
sftp -P 2222 root@device
```

Starting an emergency SSH server expands the target's attack
surface; use explicit host keys, authentication policy, bind addresses, and a
short lifetime appropriate to the incident.

Dropbear remains optimized and stripped. It is non-PIE on MIPS because the
pinned Zig MIPS runtime cannot currently link this complex program as static
PIE; other Dropbear targets retain static PIE.

### Tunnels over SSH: tunpipe and pppd

`tunpipe` is this repository's own program, linked into `dropbearmulti` like
`dbclient` ([source](../tunpipe/tunpipe.c)). The same program also ships as
`tunpipe-standalone`, a small separate binary for targets that need only the
tunnel; it ignores its own name, so it can be copied to a target as
`tunpipe`. It joins two hosts with an IPv4
point-to-point TUN interface by exchanging length-prefixed packets over a
byte stream, usually the stdin and stdout of a `dbclient` session. It is a
replacement for OpenSSH's `ssh -w`, which Dropbear does not implement. Nothing
new listens: the SSH server runs `tunpipe` as the session command, and either
end tears down its interface, routes, namespace, and NAT rules when the stream
ends.

```sh
# Client: route 192.168.10.0/24 through the server, which masquerades it.
tunpipe -l 10.9.0.2 -p 10.9.0.1 -r 192.168.10.0/24 -- \
    dbclient -K 15 root@server tunpipe -l 10.9.0.1 -p 10.9.0.2 -N
```

`-n NAME` puts the client's tunnel in a new network namespace,
`/run/netns/NAME`, with a default route through it. The SSH session itself
stays in the host namespace, so the tunnel cannot capture its own transport.
Programs opt in with `nsenter --net=/run/netns/NAME COMMAND`. Under a
systemd unit with its own mount namespace (`PrivateTmp=`, `ProtectSystem=`),
the namespace file is invisible to the host unless the unit sets
`MountFlags=shared`. Name resolution
inside the namespace still uses the host's `/etc/resolv.conf`; a resolver on
`127.0.0.53` is not reachable there.

`-N` adds an nftables table, `tunpipe_<interface>`, that masquerades traffic
from the peer address and drops anything arriving on the tunnel from another
source, and it enables `net.ipv4.ip_forward`. Only the peer's own address
is carried; routing a client-side LAN un-NATed through the server is not
supported. It needs
`nft` on `PATH`, and it leaves forwarding enabled on exit because other
tunnels may depend on it. A host firewall that drops forwarded traffic still
needs its own rule.

Both ends need `/dev/net/tun` and `CAP_NET_ADMIN`. On the server, pin the
command and its addresses to a dedicated key in `authorized_keys`, so that the
key can open the tunnel and nothing else:

```text
command="tunpipe -l 10.9.0.1 -p 10.9.0.2 -N",restrict ssh-ed25519 AAAA...
```

Each client needs its own address pair. `tunpipe` refuses a peer that does
not answer with its handshake, which also catches a login shell that prints a
banner on stdout. Each end sends a keepalive every 10 seconds and
exits after 45 seconds without hearing from the other, so a server whose
client vanished releases its interface; a client that reconnects sooner
should use a fresh address pair or wait. The tunnel is IPv4 only and has no
reconnect logic; run it from a loop or a service manager. It carries TCP inside TCP, which works well
on clean links and poorly on lossy ones, where WireGuard is the better choice.

`pppd` is built without plugins, OpenSSL, PAM, or libpcap. MS-CHAP and MPPE use
its built-in crypto; EAP-TLS, PEAP, active filters, multilink, and CBCP are
omitted. It can run the same kind of tunnel through PPP framing, provided both
kernels have `CONFIG_PPP` and `CONFIG_PPP_ASYNC`:

```sh
pppd noauth pty 'dbclient root@server pppd notty noauth' 10.9.0.2:10.9.0.1
```

The `chat` modem scripting tool is not included. Per-file pppd notices are
collected into `licenses/ppp/PPPD-NOTICES`.

### WireGuard without the kernel module: wireguard-go

`wireguard-go` is the userspace WireGuard implementation, for kernels older
than 5.6 or built without `CONFIG_WIREGUARD`, which covers most of the
embedded and vendor kernels this kit is carried to. It only runs the
interface; the bundled `wg` configures it exactly as it would the kernel
module, through the control socket `wireguard-go` creates at
`/var/run/wireguard/<interface>.sock`. `wg-quick` is not included, so set
the addresses and routes with `ip`:

```sh
umask 077
wg genkey > wg0.key
wireguard-go wg0
wg set wg0 private-key ./wg0.key listen-port 51820 \
    peer PEER_PUBLIC_KEY endpoint 192.0.2.40:51820 allowed-ips 10.8.0.0/24
ip address add 10.8.0.2/24 dev wg0
ip link set wg0 up
wg show wg0
```

`wireguard-go wg0` detaches. On Linux it always prints a notice recommending
the kernel module, whether or not the kernel has one, unless
`WG_PROCESS_FOREGROUND=1` is set; on a kernel that has it, prefer the module.
`-f` keeps it in the foreground, `LOG_LEVEL=verbose` logs handshakes, and stopping the process
removes the interface. It needs `/dev/net/tun`, `CAP_NET_ADMIN`, and a
writable `/var/run/wireguard`. As a Go program it needs Linux 3.2 or later
and is not built for `powerpc` or `powerpc64`; see the
[architecture guide](ARCHITECTURES.md#go-tools).

The modules it links are listed with their versions and `go.sum` hashes in
`licenses/wireguard-go/go-modules.tsv`, with each module's license and
patent notices under `licenses/wireguard-go/modules/`; Go's own runtime
notices are under `licenses/go/`.

### Serial consoles: picocom and lrzsz

`picocom` is a small serial terminal. Upstream's arbitrary (non-standard)
baud-rate support relies on glibc's termios layout and is enabled only on
x86, so it is compiled out on every target: the standard rates up to
4000000 are available, but a rate such as 74880 is not. Ports are locked with
`flock(2)`; UUCP lock files are not used. Exit with `C-a C-x`.

```console
picocom -b 115200 /dev/ttyUSB0
```

`sz` and `rz` are lrzsz's `lsz` and `lrz`, built without NLS. picocom's
default send and receive commands are `sz -vv` and `rz -vv -E`, so with the
kit on `PATH` a file moves over the console without a network: start `rz` on
the far end, then press `C-a C-s` in picocom and name the file. In the other
direction, run `sz FILE` on the far end and press `C-a C-r`; `-E` renames
rather than overwrites an existing local file. Any terminal that speaks
ZMODEM can drive them the same way.

Opening a serial device usually needs membership in its group (often
`dialout`) or root.

### Remote debugging: gdbserver

`gdbserver` comes from GNU GDB; GDB itself, Python, expat, debuginfod, and
the in-process agent (fast tracepoints) are not built. Debug from a host GDB
that understands the target architecture, such as `gdb-multiarch`, with the
same executable and its symbols on the host.

Running it over an SSH session's stdio needs no listener on the target:

```console
gdb ./app -ex 'target remote | dbclient root@device /tmp/statics/gdbserver - /usr/bin/app'
```

`gdbserver --attach - PID` attaches to a running process instead. A TCP
listener (`gdbserver 127.0.0.1:2345 PROGRAM`) gives anyone who can reach it
full control of the debugged process, so keep it on loopback and forward it
over SSH. There is no `libthread_db` in a static musl build: threads are
listed and stepped through ptrace, but GDB cannot use `libthread_db` to
inspect thread-local variables. Debugging needs ptrace permission over the
process, which root normally has, subject to Yama `ptrace_scope` and
LSM policy.

### Compression and archives

`zstd` has no pre-1.0 (v0.1 to v0.7) format support, no gzip, xz, or
lz4 modes (use `pigz` and `xz`), and, like upstream's `zstd-frugal`, no
benchmark (`-b`), dictionary training (`--train`), or tracing. `-T0` uses
every core. `xz` is built with liblzma's `--enable-small`, a little slower
for a 15% smaller binary; `xzdec`, `lzmadec`, the `lzma`/`unlzma` links, and
the `xzgrep`-style scripts are not built. `bzip2` has the `bunzip2` and
`bzcat` links but not `bzip2recover`. `pigz` is built without Zopfli: `-11`
is accepted but compresses only at the default level, so use `-9`. `unpigz`
decompresses.

zlib, libbz2, liblzma, and libzstd are each built once and linked statically
into the tools above and into libarchive. rsync and Nmap keep their own
bundled zlib copies.

`bsdtar` and `bsdcpio` come from libarchive. They read and write tar (ustar,
pax, GNU), cpio, zip, 7z, ISO 9660, ar, mtree, and WARC, write shar, and read
RAR (v4 and v5), CAB, and LHA, through gzip, bzip2, xz, lzma, lzip, zstd, and
`compress` (.Z) filters. Encrypted 7z archives cannot be read by any
libarchive build. Left out to save size: any crypto library, so AES-encrypted
zip archives cannot be read (traditional zip encryption works, with
`--passphrase`) and mtree digests are left out; libxml2 and
expat, so no xar; lz4 and lzo; iconv, so there is no `hdrcharset` option and
names in legacy character sets are not converted; and libacl, so ACLs are
neither stored nor restored. Extended attributes work. `bsdcat`
and `bsdunzip` are not built: decompress a bare stream with `zstdcat`, `xzcat`,
`bzcat`, or `unpigz -c` (a bare `.Z` stream has no decompressor in the kit),
and extract a zip with `bsdtar -xf FILE.zip`.

### Pipe transfer: pv and mbuffer

`pv` is built without ncurses or NLS. `mbuffer` is built without `--md5`,
which would need a crypto library. Under QEMU user-mode emulation `mbuffer`
warns that it cannot advise memory handling; the transfer is unaffected.

### Rsync

Rsync includes IPv4/IPv6, local socket-pair support, and bundled popt and
zlib. ACL, xattr, iconv, IDN, OpenSSL, xxHash, zstd, and LZ4 integrations are
disabled. Preserve those limitations when designing backup or migration
workflows: a successful copy does not imply ACL or extended-attribute
preservation.

### Lsof

Lsof reads Linux procfs. Results depend on procfs being mounted and on its
`hidepid` setting, namespaces, user IDs, Linux security modules, and other
kernel restrictions. An empty or partial listing does not necessarily mean
the resource is unused.

### Nftables

Nftables uses static libnftnl, libmnl, and bundled mini-gmp. The interactive readline
shell, JSON output, and xtables compatibility are disabled. Listing or changing rules
depends on kernel nftables support and normally requires `CAP_NET_ADMIN`; rule changes
can immediately cut off network access.

### Filesystems, SMART, and NVMe

E2fsprogs includes the ext2/3/4 checker, metadata inspection, tuning, and filesystem
creation commands. Its libraries are bundled into the executables. `smartctl` carries
its drive database inside the binary, so it needs no separate runtime database. The
NVMe command is built without json-c; JSON-formatted output and features that depend on
that library are unavailable.

These programs operate on block devices and can destroy data when used in write,
repair, format, firmware, or sanitize modes. Identify the device precisely, prefer
read-only inspection first, and follow the filesystem or hardware vendor's recovery
procedure. Device access usually requires root and the corresponding kernel driver.

### MTR and hardware tools

MTR is built without its curses interface; use report mode. CAN, ISO-TP, I²C,
and SPI commands require the target kernel drivers and relevant network
interfaces or device nodes. Write-oriented bus commands can alter hardware
state—inspect the device documentation first.

### Util-linux profile

The util-linux build contains the namespace tools `nsenter`, `unshare`,
`lsns`, `setpriv`, and `findmnt`, and the block-device and system tools
`lsblk`, `blkid`, `sfdisk`, `losetup`, `mount`, `umount`, and `dmesg`, with
static libblkid, libmount, libsmartcols, libfdisk, and libcap-ng as needed.
NLS, udev, SELinux, systemd, libmagic, cryptsetup, ncurses, readline, and
Python integrations are disabled. Without udev, `lsblk` reads device
properties from sysfs and probes, so udev-only columns are empty. `mount` and
`umount` are not setuid. The interactive `fdisk` and `cfdisk` are not built;
`sfdisk` covers scripted partitioning and `sfdisk --dump` backs up a
partition table:

```console
lsblk --output NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
blkid
sfdisk --dump /dev/DEVICE > DEVICE.sfdisk
dmesg --level err,warn --ctime
```

### Connection tracking: conntrack

`conntrack` comes from conntrack-tools with libnetfilter_conntrack,
libnfnetlink, and the bundle's libmnl. Only the CLI is built: no
`conntrackd`, `nfct`, or user-space helpers. It lists, filters, watches,
and deletes kernel connection-tracking entries, for example to find NAT state
or flush a stuck flow. It needs `CAP_NET_ADMIN` and the `nf_conntrack`
netlink interface (`CONFIG_NF_CT_NETLINK`).

```console
conntrack -L -p tcp --dport 443
conntrack -E -e NEW,DESTROY
conntrack -S
```

### Wi-Fi: iw

`iw` is the nl80211 configuration tool, statically linked with libnl-3 and
libnl-genl-3. Scans, station dumps, regulatory and interface changes go
through the kernel's cfg80211 driver; the legacy wireless extensions
(`iwconfig`) are not used. Reading state works unprivileged on most kernels;
scanning and changes need `CAP_NET_ADMIN`.

```console
iw dev
iw dev wlan0 link
iw dev wlan0 station dump
iw reg get
```

### Out-of-band management: ipmitool

`ipmitool` comes from upstream's archived GitHub repository, whose last
release is the one pinned. It talks to a local BMC
through the OpenIPMI driver (`/dev/ipmi0`, from `ipmi_devintf` and
`ipmi_si`), and to a remote one over IPMI 1.5 `lan` or IPMI 2.0 `lanplus`,
which uses the bundle's OpenSSL. The interactive `ipmitool shell`, the
`ipmievd` daemon, and the USB and D-Bus interfaces are not built.
ipmitool names vendors from the IANA enterprise-number list, which is not
packaged: some commands print `IANA PEN registry open failed` and show
numeric manufacturer IDs instead. ipmitool reads it from
`/usr/share/misc/enterprise-numbers` or
`~/.local/usr/share/misc/enterprise-numbers`.

```console
ipmitool sdr elist
ipmitool sel elist
ipmitool -I lanplus -H 192.0.2.30 -U ADMIN -E chassis status
```

`-E` reads the password from `IPMI_PASSWORD` so it stays out of the process
list. IPMI over the network is weakly authenticated; keep BMCs on an isolated
management network.

### Raw flash and UBI: mtd-utils

The selected mtd-utils programs inspect and rewrite MTD NOR and NAND flash and
manage UBI: `flash_erase`, `flashcp`, `nanddump`, `nandwrite`, `mtdinfo`,
`ubiattach`, `ubidetach`, `ubinfo`, `ubimkvol`, `ubirmvol`, and
`ubiupdatevol`. Image builders such as `mkfs.ubifs`, `ubinize`, and
`mkfs.jffs2`, and `ubiformat`, are not included, so no compression or crypto
library is linked. Create images on a workstation.

```console
mtdinfo --all
nanddump --bb=dumpbad --file mtd2.img /dev/mtd2
ubinfo --all
```

Erasing or writing flash can brick a device, and NAND bad-block handling
differs between bootloaders and kernels. Dump every partition first and
confirm the partition map (`/proc/mtd`). The programs need root and the
kernel's MTD character devices (`/dev/mtdN`) or UBI devices.
`flashcp` is BSD-licensed; its notice is collected into
`licenses/mtd-utils/MTD-UTILS-BSD-NOTICES`.

## Extra archive: rclone, croc, crictl, and ctr

These tools are several times the size of anything in the main archive, so
they are packaged apart. Each is a static Go binary built with cgo disabled,
`-trimpath`, and `-ldflags="-s -w -buildid="` (plus upstream's `-X` version
stamp where it has one), without UPX; the archive is
compressed with `xz -9`, whose 64 MiB window lets the tools share their common
Go runtime and modules, so decompressing it needs about 65 MiB of memory.
Unpack it on a staging machine for a target with less. Extract it beside the
main archive and add both directories to `PATH`:

```sh
tar -xJf statics-extra-aarch64.tar.xz
export PATH="/tmp/statics/aarch64:/tmp/statics/aarch64-extra:$PATH"
```

Every module each tool links is listed in
`licenses/<source>/go-modules.tsv` (`rclone`, `croc`, `cri-tools`,
`containerd`), with its license files beside it.

### rclone, trimmed

The bundled `rclone` is not upstream's full build, which links about 70
backends and 80 commands into 20 MB (xz) per architecture. It is built from a
smaller main package,
[`patches/go-mains/rclone/cmd/statics/main.go`](../patches/go-mains/rclone/cmd/statics/main.go),
compiled inside rclone's source tree against rclone's own `go.mod` and
`go.sum`. It is about 7.5 MiB (xz) on x86-64 and links:

| | Included |
| --- | --- |
| Backends | `local`, `s3` (AWS and every S3-compatible provider rclone knows), `sftp`, `http` (read-only), `webdav`; `crypt` also comes with rclone's core |
| Commands | `copy`, `copyto`, `sync`, `ls`, `lsf`, `lsd`, `cat`, `rcat`, `check`, `size`, `config`, `version`, plus cobra's `help` and `completion` |

Everything else is left out: other backends (Google Drive, OneDrive, Azure
Blob, B2, Swift, FTP, SMB, ...), `mount` and `serve`, `move`, `delete`,
`purge`, `mkdir`, `lsjson`, `hashsum`, `bisync`, `ncdu`, `rc` and `rcd`, and
`selfupdate`. Flags of included commands work as upstream documents. Remotes
can come from `rclone config`, which writes `~/.config/rclone/rclone.conf`,
from `RCLONE_CONFIG_<NAME>_<OPTION>` variables, or inline, which leaves
nothing on the target:

```sh
rclone lsf :sftp,host=192.0.2.10,user=admin,key_file=/tmp/id_ed25519:/var/log
rclone copy /var/log/app ":s3,provider=Minio,endpoint='http://192.0.2.20:9000',env_auth=true:backup/app"
rclone check /srv/data ":webdav,url='https://dav.example.net/remote.php/dav/files/me':data" --one-way
```

Quote an option value that contains a colon or comma, as the URLs above do.

To ask for another backend or command, open an issue naming it and why it
helps on a broken host; each one adds size to every architecture. To build
it yourself, add its import (`github.com/rclone/rclone/backend/<name>` or
`github.com/rclone/rclone/cmd/<name>`) to that `main.go`: the module fetch
runs `go list -deps` on it, so the new modules are fetched, checked against
rclone's `go.sum`, and given license notices without any other change.

### croc: uses its author's public relay by default

> [!WARNING]
> Out of the box, `croc send` and `croc receive` connect to a **public relay
> run by croc's author** (`croc.schollz.com:9009`, `croc6.schollz.com` for
> IPv6, and the `*.getcroc.com` pool). Files are end-to-end encrypted with a
> key derived from the code phrase (PAKE), but that third party sees both
> endpoints' addresses, the transfer's timing and size, and its availability
> decides whether a transfer works. Each send and receive also asks
> `api.github.com` whether a newer croc exists. For anything sensitive, or a
> network without the internet, run your own relay.

The bundled `croc` is built with upstream's `croc_no_tailcat` tag, which
leaves out the Tailscale-based DERP transport and so cuts its size by more
than half: transfers go through a croc relay (or directly on a LAN), and
`croc ssh` is not available. The relay defaults are unchanged from upstream.

Run a relay on any host both ends can reach (it listens on TCP 9009 to 9013)
and point both sides at it, with a relay password other than the default
`pass123`:

```sh
# Relay host
CROC_PASS='long-random-relay-password' croc relay

# Sender and receiver
export CROC_RELAY=192.0.2.10:9009 CROC_PASS='long-random-relay-password'
croc --no-update-check send ./capture.pcap       # prints a code phrase
CROC_SECRET='CODE-PHRASE' croc --no-update-check  # on the receiver
```

`croc --relay 192.0.2.10:9009 --pass ...` does the same as the variables,
but arguments, like a code phrase given as one, are visible in `ps`; that is
why croc takes the receiver's code from `CROC_SECRET` on Linux. Setting
`CROC_NO_UPDATE_CHECK=1` also stops the update check. Do not run
`croc update`: it replaces the binary with upstream's release build. Upstream
documents the relay and its options in its
[README](https://github.com/schollz/croc#self-host-relay).

### Container runtimes: crictl and ctr

`crictl` speaks the Kubernetes Container Runtime Interface to containerd or
CRI-O; `ctr` speaks containerd's own API, which also shows what the kubelet
cannot (snapshots, leases, content, and non-Kubernetes namespaces). Both need
root, or access to the runtime's socket, and neither needs anything else from
the host:

```sh
export CONTAINER_RUNTIME_ENDPOINT=unix:///run/containerd/containerd.sock
# CRI-O: unix:///var/run/crio/crio.sock
crictl pods
crictl ps -a
crictl logs --tail 100 CONTAINER_ID
crictl inspect CONTAINER_ID | jq '.info.pid'
crictl images

ctr namespaces ls
ctr -n k8s.io containers ls
ctr -n k8s.io tasks ls
ctr -n k8s.io images ls
ctr -n k8s.io snapshots ls
ctr -n k8s.io snapshots usage
```

`ctr -a PATH` selects another socket (k3s uses
`/run/k3s/containerd/containerd.sock`). Commands that create containers
(`ctr run`, `ctr tasks start`) still need the host's runc and shims, which
are not bundled. containerd's build tags (`no_btrfs`, `no_devmapper`,
`no_zfs`, `no_cri`, `no_rdt`, `no_systemd`, `no_tracing`) only remove
daemon plugins that `ctr` does not link, so building with them leaves its
size unchanged and none is used; `no_grpc` does not build.

## Privilege guide

Exact rules vary by kernel and security policy, but these are common:

| Operation | Typical requirement |
| --- | --- |
| TCP connect checks, DNS, HTTP, TLS | Unprivileged network access |
| ICMP/raw probes, some Nmap scan modes, packet capture | root or capabilities such as `CAP_NET_RAW` |
| Address, route, link, WireGuard, bridge, or traffic-control changes | root or `CAP_NET_ADMIN` |
| Inspect or change nftables rules | commonly root or `CAP_NET_ADMIN` |
| Trace, inspect, or debug another user's process | root, ptrace permission, and compatible LSM policy |
| Open a serial console | the device's group (often `dialout`) or root |
| Enter another process's namespaces | commonly root or `CAP_SYS_ADMIN` in the owning user namespace |
| Create user/network/mount/PID namespaces | kernel namespace support plus the applicable sysctl, LSM, seccomp, and capability policy |
| Read I²C/SPI devices or CAN interfaces | suitable device/interface permissions and drivers |
| Inspect, repair, format, or manage block devices | usually root, device access, and the matching kernel driver |
| Mount, unmount, or attach loop devices | root or `CAP_SYS_ADMIN` |
| Read the kernel log | root or `CAP_SYSLOG` when `kernel.dmesg_restrict=1` |
| List or change connection tracking; scan or configure Wi-Fi | `CAP_NET_ADMIN` and the kernel's netlink support |
| Read, erase, or write MTD flash or UBI volumes | root and the kernel's MTD/UBI devices |
| Query a local BMC | root and `/dev/ipmi0` (`ipmi_devintf`) |
| Inspect containers, images, and snapshots with `crictl` or `ctr` | root or access to the runtime's socket |
| Start a listener on a privileged port | root or `CAP_NET_BIND_SERVICE` |

Do not add capabilities to the whole toolkit directory. If policy permits,
grant the minimum capability to the minimum executable and remove it after
the diagnostic session.

For build failures and runtime error messages, see
[troubleshooting](TROUBLESHOOTING.md).
