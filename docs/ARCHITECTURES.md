# Architecture and ABI guide

Choosing the CPU family is not enough for embedded Linux. Endianness, word
size, floating-point ABI, minimum ISA, and kernel age all affect whether an
otherwise valid ELF executable starts.

For build commands and host requirements, see [Building](BUILDING.md). For
runtime errors after choosing a target, see
[Troubleshooting](TROUBLESHOOTING.md).

## Supported targets

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

Common `uname -m` values narrow the choice but do not fully identify the ABI:

| Common output | Likely target family | Confirm before choosing |
| --- | --- | --- |
| `x86_64` | `x86_64` | Whether the kernel/userspace can execute 64-bit ELF |
| `i386` through `i686` | `i686` | CPU is Pentium II class or newer |
| `aarch64`, `arm64` | `aarch64` | 64-bit userspace, not only a 64-bit-capable CPU |
| `armv6l` | `armv6-hardfloat` candidate | Existing userspace uses the hard-float ABI |
| `armv7l`, `armv7*` | an ARMv7 target | Soft-float versus hard-float userspace |
| `mips` | `mips` candidate | Big-endian, 32-bit o32 userspace |
| `mipsel` | `mipsel` candidate | Little-endian, 32-bit o32 userspace |
| `ppc`, `powerpc` | `powerpc` candidate | 32-bit big-endian hard-float userspace |
| `ppc64` | `powerpc64` candidate | Big-endian userspace |
| `ppc64le` | `powerpc64le` | Little-endian userspace |
| `riscv64` | `riscv64` | Required baseline instructions are exposed |
| `s390x` | `s390x` | 64-bit userspace |

A kernel can report the CPU's native architecture while running a 32-bit
userspace. Prefer the ELF header of a known-working executable such as
`/bin/sh` when the two disagree.

### ARM float ABI

For 32-bit ARM, inspect an existing executable:

```console
readelf -A /bin/sh 2>/dev/null | grep -E 'Tag_ABI_VFP_args|Tag_CPU_arch'
find /lib -maxdepth 2 \( -name '*armhf*' -o -name 'ld-linux*.so*' \) 2>/dev/null
```

`Tag_ABI_VFP_args: VFP registers` and an `armhf` loader indicate hard-float.
Absence of the tag is not conclusive for every toolchain, so compare multiple
executables or the firmware's package architecture. The bundle is static, but
the target's existing loader names are useful ABI evidence.

### Endianness and word size

For MIPS and PowerPC, do not infer endianness from a product name:

```console
readelf -h /bin/sh 2>/dev/null | grep -E 'Class:|Data:|Machine:|Flags:'
```

`ELF32` versus `ELF64` establishes word size, and the `Data` line establishes
little versus big endian. MIPS ELF flags can also reveal ABI details. The
first release supports 32-bit MIPS o32 soft-float, not MIPS64 or alternate
MIPS ABIs.

Musl removes the dependency on a target's installed libc. It does not remove
dependencies on Linux kernel behavior. Very old vendor kernels may lack
syscalls assumed by current upstream tools, and seccomp policies can produce
similar failures.

## Build host versus target

The Docker build host must be `amd64` or `arm64` because those are the pinned
Zig distributions provided by the toolchain stage. This does not limit the
target matrix: either supported host architecture can build all rows above.

The target device does not need Docker, Zig, musl, or QEMU. It needs a
compatible Linux kernel, CPU/ABI, execute permission, and any kernel
features/privileges required by the selected utility.

## QEMU coverage

Each row names a QEMU user-mode runner in `architectures.tsv`. Verification
executes unprivileged smoke or version checks for BusyBox/netcat, socat,
Dropbear, the iproute2 tools, WireGuard, OpenSSL, tcpdump, curl, iperf3,
ethtool, strace, jq, drill, mtr, i2c-tools, Nmap/Ncat, rsync, lsof, and the
util-linux namespace tools. Every physical executable, including the CAN,
ISO-TP, and SPI utilities, is checked for static linkage and the absence of a
dynamic program interpreter. Nmap's runtime data files are checksum-verified
separately. QEMU is an instruction/ABI smoke test, not proof that privileged
networking, namespace entry, or procfs inspection works on a real kernel and
device.

CI builds every listed target. Locally, `make smoke ARCH=<name>` supplies QEMU
inside the container. `make verify ARCH=<name>` uses an existing exported
tree and requires the matching QEMU user executable on the host, except for
the implemented x86-64 native fast path.

## Unsupported targets

ARMv5, MIPS64, and LoongArch64 are intentionally deferred for known toolchain
or dependency-chain reasons; Darwin and Windows are separate future platform
families. The current rationale and criteria for revisiting them are in the
[roadmap](ROADMAP.md).

Do not rename a “near enough” binary to another target. An `Exec format error`
usually means the wrong ELF class, machine, endianness, or ABI. An `Illegal
instruction` usually means the selected CPU baseline is too new. Diagnose
either with the [runtime troubleshooting guide](TROUBLESHOOTING.md).
