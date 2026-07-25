# Architecture and ABI guide

Choosing the CPU family is not enough for embedded Linux. Endianness, word
size, floating-point ABI, minimum ISA, and kernel age all affect whether an
otherwise valid ELF executable starts.

| Build name | Zig target | Minimum CPU/profile | ABI notes |
| --- | --- | --- | --- |
| `x86_64` | `x86_64-linux-musl` | x86-64 baseline | 64-bit little-endian |
| `i686` | `x86-linux-musl` | Pentium II | 32-bit little-endian |
| `aarch64` | `aarch64-linux-musl` | AArch64 baseline | 64-bit little-endian |
| `armv6-hardfloat` | `arm-linux-musleabihf` | ARM1176JZF-S | EABI hard-float; Raspberry Pi 1 class |
| `armv7-hardfloat` | `arm-linux-musleabihf` | Cortex-A7 | EABI hard-float; common ARMv7 Linux |
| `armv7-softfloat` | `arm-linux-musleabi` | Cortex-A7 | EABI soft-float for firmware without hard-float userspace |
| `mips` | `mips-linux-musleabi` | MIPS32 | 32-bit big-endian, soft-float o32 ABI |
| `mipsel` | `mipsel-linux-musleabi` | MIPS32 | 32-bit little-endian, soft-float o32 ABI |
| `powerpc` | `powerpc-linux-musleabihf` | baseline PowerPC | 32-bit big-endian, hard-float ABI |
| `powerpc64` | `powerpc64-linux-musl` | baseline PowerPC64 | 64-bit big-endian |
| `powerpc64le` | `powerpc64le-linux-musl` | baseline PowerPC64LE | 64-bit little-endian |
| `riscv64` | `riscv64-linux-musl` | RV64 baseline | 64-bit little-endian |
| `s390x` | `s390x-linux-musl` | IBM Z baseline | 64-bit big-endian |

## Identifying a device

When a shell is available, gather at least:

```console
uname -m
getconf LONG_BIT 2>/dev/null || true
readelf -h /bin/sh 2>/dev/null || file /bin/sh
cat /proc/cpuinfo
```

For 32-bit ARM, inspect the ELF attributes or the installed dynamic loader to
distinguish soft-float from hard-float. For MIPS and PowerPC, do not infer
endianness from the marketing name; inspect an existing ELF header.

Musl removes the dependency on a target's installed libc. It does not remove
dependencies on Linux kernel behavior. Very old vendor kernels may lack
syscalls assumed by current upstream tools, and seccomp policies can produce
similar failures.

## QEMU coverage

Each row names a QEMU user-mode runner in `architectures.tsv`. Verification
executes unprivileged smoke or version checks for BusyBox/netcat, socat,
Dropbear, the iproute2 tools, WireGuard, OpenSSL, tcpdump, curl, iperf3,
ethtool, strace, jq, drill, mtr, i2c-tools, Nmap/Ncat, rsync, and lsof. Every
physical executable, including the CAN, ISO-TP, and SPI utilities, is checked
for static linkage and the absence of a dynamic program interpreter. Nmap's
runtime data files are checksum-verified separately. QEMU is an instruction/
ABI smoke test, not proof that privileged networking or procfs inspection
works on a real kernel and device.
