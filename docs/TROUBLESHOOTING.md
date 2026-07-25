# Troubleshooting

Start by identifying which stage failed:

1. repository validation;
2. Buildx/toolchain setup;
3. source download or checksum verification;
4. compilation/linking;
5. artifact export;
6. static inspection or QEMU execution;
7. execution on the real device.

Preserve the first meaningful error from the failing stage. Later errors are
often consequences.

## Buildx is unavailable

Typical messages mention an unknown `buildx` command, no builder, or an
unsupported exporter.

```console
docker version
docker buildx version
docker buildx ls
docker buildx inspect --bootstrap
```

Install or enable the Buildx plugin supplied for the Docker installation.
The repo uses multi-stage Dockerfiles, cache mounts, named targets, local
output, and `--load`; a legacy `docker build` implementation is insufficient.

## Unsupported builder architecture

The message:

```text
unsupported builder architecture: ...
```

refers to the Docker host, not `ARCH`. The toolchain image supports `amd64`
and `arm64` hosts. Run Buildx on one of those hosts; changing the requested
target does not resolve this error.

## Source download fails

All source URLs and SHA-256 values come from `sources.lock`.

- A connection or HTTP error can be retried after network/proxy service is
  restored.
- A checksum mismatch must not be bypassed. Confirm that the lock file came
  from the intended commit and investigate whether upstream replaced an
  archive.
- If a reviewed source update is intended, use
  `scripts/update_sources.py --write --only nmap` (substituting the component)
  and review the resulting URL, version, and digest.

The Socat archive is the documented HTTP exception. Its canonical host has a
certificate-name problem, so integrity depends on the reviewed SHA-256 pin.
See [the security policy](../SECURITY.md).

## A build exhausts memory or disk

BuildKit retains source, toolchain, and compiler layers. First confirm host
capacity with the Docker installation's normal disk-usage tooling. `make
clean` removes only repository-local `.build/` and `dist/`; it does not prune
Docker's shared cache.

Cache pruning affects other projects that use the same builder, so it is an
administrator decision rather than a repository command. On a small host,
build one architecture at a time instead of `make all`.

## A source update no longer compiles

An update PR is not complete when `sources.lock` changes successfully. New
upstream releases can change:

- configure options and cross-compilation probes;
- bundled dependency choices;
- license files or expressions;
- runtime data paths;
- patch context;
- minimum kernel or compiler requirements.

Review the source's function in `scripts/builders/`, any file under
`configs/` or `patches/` that it consumes, `components.tsv`, and the
expectations in `scripts/verify.sh`. Validate at least a representative
64-bit target, a 32-bit target, and an opposite-endian target when the changed
code is architecture-sensitive.

## `make smoke` succeeded but `dist/<arch>` is missing

This is expected. `make smoke` validates the Docker `test` target and loads a
test image; it does not use the local artifact exporter. Run:

```console
make build ARCH=mipsel
```

or use `make package ARCH=mipsel` to rebuild and export a release-shaped
archive.

## Local verification cannot find QEMU

`make verify` names the required user-mode emulator from `architectures.tsv`.
Install QEMU user-mode support on the host, use the containerized check:

```console
make smoke ARCH=mipsel
```

or explicitly accept static-only inspection:

```console
SKIP_QEMU=1 make verify ARCH=powerpc
```

Static-only inspection does not satisfy the normal CI/release gate.

## `Exec format error` on a device

The executable's CPU, endianness, word size, or ABI does not match the
destination. Compare the target bundle with:

```console
uname -m
readelf -h /bin/sh 2>/dev/null || file /bin/sh
readelf -h /path/to/downloaded/tool
```

For ARM, confirm soft-float versus hard-float. For MIPS and PowerPC, confirm
endianness from an existing ELF file. See the
[architecture guide](ARCHITECTURES.md).

## `Illegal instruction`

The CPU is older or implements a narrower ISA than the selected target, or a
virtualized/emulated CPU does not expose the expected instructions. Confirm
the exact CPU in `/proc/cpuinfo` and choose the lowest compatible build.
Current ARM targets begin at ARMv6 hard-float and ARMv7 soft/hard-float;
ARMv5 is intentionally unsupported.

## `No such file or directory` for a file that exists

For a dynamically linked executable this often means a missing program
interpreter, but repo verification rejects that condition. In this bundle,
also check:

- that the file was transferred without truncation;
- execute permission on the file and mount;
- CPU/ABI compatibility;
- a script's shebang, if the failing path is not one of the ELF payloads.

Run `file TOOL` and compare its digest with `SHA256SUMS`.

## `Operation not permitted` or incomplete results

Static linking does not grant privileges. Common requirements include:

- `CAP_NET_RAW` for raw probes and packet capture;
- `CAP_NET_ADMIN` for interface, route, WireGuard, bridge, and traffic-control
  changes;
- ptrace permission for another process;
- readable procfs entries for Lsof;
- correct device-node permissions and drivers for I²C/SPI;
- enabled SocketCAN/ISO-TP support for CAN tools.

Containers, namespaces, seccomp, Linux security modules, and vendor kernels
can restrict these operations even for uid 0.

## Nmap cannot find its data files

Keep `share/nmap/` with the executable and pass:

```console
nmap --datadir /path/to/statics/share/nmap TARGET
```

Alternatively install the data at `/usr/share/nmap`. `ncat` does not require
the Nmap database directory for ordinary connect/listen use.

## Curl reports a CA certificate error

The default CA path is `/etc/ssl/certs/ca-certificates.crt`. Supply the
destination's trusted bundle:

```console
curl --cacert /path/to/ca-bundle.pem https://example.com/
```

Do not treat `--insecure` as a permanent fix; it disables certificate
verification.

## Lsof shows less than expected

Confirm that `/proc` is mounted and inspect its mount options. `hidepid`,
process namespaces, user ownership, ptrace restrictions, and security modules
can hide file descriptors or processes. Run Lsof in the same namespaces as
the target process when possible.

## Rsync does not preserve metadata

The compact profile intentionally omits ACL and extended-attribute support.
It also omits iconv, OpenSSL, xxHash, zstd, and LZ4 integrations. Use a build
profile with those features before relying on rsync for metadata-complete
backup or migration.

## QEMU passed but the real operation fails

QEMU smoke tests validate instruction/ABI startup and representative
unprivileged command paths. They cannot prove:

- compatibility with an old vendor kernel;
- privileged network operations;
- packet capture or TUN support;
- device ioctls and drivers;
- procfs visibility;
- seccomp or Linux security-module policy;
- behavior on the physical network or bus.

Reproduce on the real device with the least disruptive command possible and
record its kernel version, architecture, capabilities, namespaces, and exact
error.

## Before reporting a problem

Include:

- the repository commit;
- build host CPU, Docker version, and Buildx version;
- requested architecture;
- the command that failed and its complete first error;
- whether the failure was during build, local verification, QEMU, or real
  device execution;
- destination `uname -a`, `/proc/cpuinfo`, and an ELF header when relevant.

Do not attach credentials, private keys, packet captures, customer addresses,
or other sensitive incident data.
