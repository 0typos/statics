#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [[ $# -ne 2 ]]; then
    echo "usage: $0 OUTPUT_DIR ARCH" >&2
    exit 2
fi

output_dir=$1
arch=$2
record=$(awk -F '|' -v wanted="$arch" '
    $0 !~ /^#/ && $1 == wanted { print; found++ }
    END { if (found != 1) exit 1 }
' "$repo_root/architectures.tsv") || {
    echo "unknown architecture: $arch" >&2
    exit 2
}
IFS='|' read -r _ _ _ qemu _ go_env tcc_cpu <<<"$record"

required_binaries=(
    busybox socat dropbearmulti
    ip ss bridge tc wg nft
    openssl tcpdump curl iperf3 ethtool strace jq drill mtr mtr-packet
    candump cansend cangen canplayer cansniffer
    isotpdump isotprecv isotpsend slcand canbusload
    i2cdetect i2cdump i2cget i2cset i2ctransfer
    spi-config spi-pipe
    nmap ncat rsync lsof
    nsenter unshare lsns setpriv findmnt
    e2fsck dumpe2fs tune2fs mke2fs smartctl nvme pppd tunpipe-standalone
    picocom sz rz gdbserver
    sftp-server lsblk blkid sfdisk losetup mount umount dmesg
    conntrack ipmitool iw
    flash_erase flashcp nanddump nandwrite mtdinfo
    ubiattach ubidetach ubinfo ubimkvol ubirmvol ubiupdatevol
    zstd xz bzip2 pigz bsdtar bsdcpio pv mbuffer
    kmod kexec bpftool
    ping arping tracepath traceroute ndisc6 rdisc6 rltraceroute6 tcptraceroute6
    nstat devlink rdma lldpd lldpcli ipset xtables-legacy-multi
    ebtables-legacy arptables-legacy ngrep hping3 iftop nethogs
    tcpreplay tcpprep tcprewrite dhcpdump
    tmux microsocks tinyproxy dnsmasq ser2net bash testssl.sh
    mount.cifs mount.nfs showmount udp-sender udp-receiver
    partclone.extfs partclone.fat partclone.dd partclone.restore
    partclone.chkimg partclone.info xxhsum
    sqlite3 qjs lua htop make
)
# Executables that are scripts rather than static ELF programs.
scripts=(testssl.sh)
# Go tools exist only where architectures.tsv gives a Go environment.
if [[ $go_env != none ]]; then
    required_binaries+=(wireguard-go)
fi
# Smoke checks for the extra archive, as "expected output|arguments" per
# executable. Every executable in it must have one, so an extra tool cannot
# ship without being started, and every one listed must be there. The C
# tools are on every target; the Go tools only where Go is.
# The pinned version is expected, so a version that upstream sets at link time
# cannot silently fall back to a development string.
pinned_version() { awk -F '|' -v n="$1" '$1 == n { print $2 }' "$repo_root/sources.lock"; }
declare -A extra_smoke=(
    [stunnel]="stunnel $(pinned_version stunnel)|-version"
    [openvpn]="OpenVPN $(pinned_version openvpn)|--version"
    [lftp]="Version $(pinned_version lftp)|--version"
    [aria2c]="aria2 version $(pinned_version aria2)|-v"
    [par2]="par2cmdline version $(pinned_version par2cmdline)|-V"
    [python3]="Python $(pinned_version python)|--version"
)
for binary in ar as ld nm objcopy objdump readelf strings strip; do
    extra_smoke[$binary]="(GNU Binutils) $(pinned_version binutils)|--version"
done
# tcc only where architectures.tsv names a cpu for it. Its version is the
# mob branch's, not the pinned commit.
if [[ $tcc_cpu != none ]]; then
    extra_smoke[tcc]="tcc version 0.9.|-v"
fi
if [[ $go_env != none ]]; then
    extra_smoke+=(
        [rclone]="rclone v$(pinned_version rclone)|version"
        [croc]="croc version $(pinned_version croc)|--version"
        [crictl]="crictl version v$(pinned_version cri-tools)|--version"
        [ctr]="ctr github.com/containerd/containerd/v2 v$(pinned_version containerd)|--version"
        [caddy]="v$(pinned_version caddy)|version"
        [yq]="version v$(pinned_version yq)|--version"
        [age]="v$(pinned_version age)|--version"
        [age-keygen]="v$(pinned_version age)|--version"
    )
fi

# Checks every archive must pass: metadata, licenses for exactly the
# components it should hold, its SBOM, static linkage, and SHA256SUMS.
check_archive() { # directory archive
    local dir=$1 archive=$2 name=statics-$arch
    [[ $archive == main ]] || name=statics-extra-$arch

    for metadata in BUILDINFO BUILD_RECIPES_LICENSE COMPONENTS.tsv SBOM.spdx.json \
        SHA256SUMS THIRD_PARTY_NOTICES.md sources.lock; do
        [[ -s $dir/$metadata ]] || {
            echo "missing build metadata: $dir/$metadata" >&2
            exit 1
        }
    done

    local expected
    expected=$("$repo_root/scripts/components.sh" "$arch" "$archive")
    diff <(grep -v '^#' "$dir/COMPONENTS.tsv") <(printf '%s\n' "$expected") || {
        echo "$dir/COMPONENTS.tsv does not list the $archive components for $arch" >&2
        exit 1
    }

    local source_name packages
    while IFS='|' read -r source_name _ _ _ packages; do
        [[ -d $dir/licenses/$source_name ]] || {
            echo "missing license directory: $dir/licenses/$source_name" >&2
            exit 1
        }
        find "$dir/licenses/$source_name" -type f -size +0c -print -quit |
            grep -q . || {
            echo "empty license directory: $dir/licenses/$source_name" >&2
            exit 1
        }
        # A Go tool lists the modules it links, and each has its notices.
        [[ $packages == - || $packages == runtime ]] && continue
        local module_list=$dir/licenses/$source_name/go-modules.tsv path version
        [[ -f $module_list ]] || {
            echo "missing Go module list: $module_list" >&2
            exit 1
        }
        while IFS='|' read -r path version _; do
            [[ -n $(find "$dir/licenses/$source_name/modules/$path@$version" \
                -type f -size +0c -print -quit 2>/dev/null) ]] || {
                echo "no license files for Go module $path@$version in $source_name" >&2
                exit 1
            }
        done <"$module_list"
    done <<<"$expected"

    python3 - "$dir/SBOM.spdx.json" "$name" <<'PY'
import json
import hashlib
import re
import sys
from pathlib import Path

path, name = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    document = json.load(handle)
if document.get("spdxVersion") != "SPDX-2.3":
    raise SystemExit("unexpected SPDX version")
if document.get("name") != name:
    raise SystemExit("unexpected SPDX document name")
if not document.get("packages") or not document.get("files"):
    raise SystemExit("SPDX document has no packages or files")
license_list = document.get("creationInfo", {}).get("licenseListVersion", "")
if not re.fullmatch(r"\d+\.\d+", license_list):
    raise SystemExit("invalid SPDX license-list version")

bundle = next(
    package
    for package in document["packages"]
    if package.get("name") == name
)
if bundle.get("filesAnalyzed") is not True:
    raise SystemExit("SPDX bundle does not analyze its payload files")

sha1_values = []
for file_record in document["files"]:
    filename = file_record["fileName"].removeprefix("./")
    binary = Path(path).parent / filename
    checksums = {
        checksum["algorithm"]: checksum["checksumValue"]
        for checksum in file_record.get("checksums", [])
    }
    for algorithm in ("SHA1", "SHA256"):
        digest = hashlib.new(algorithm.lower(), binary.read_bytes()).hexdigest()
        if checksums.get(algorithm) != digest:
            raise SystemExit(f"bad {algorithm} in SPDX record for {filename}")
    sha1_values.append(checksums["SHA1"])

verification_input = "".join(sorted(sha1_values)).encode("ascii")
verification_code = hashlib.sha1(verification_input).hexdigest()
recorded_code = bundle.get("packageVerificationCode", {}).get(
    "packageVerificationCodeValue"
)
if recorded_code != verification_code:
    raise SystemExit("bad SPDX package verification code")
PY

    local binary
    while IFS= read -r binary; do
        if [[ " ${scripts[*]} " == *" $binary "* ]]; then
            head -c 2 "$dir/$binary" | grep -qx '#!' || {
                echo "$binary should be a script" >&2
                exit 1
            }
            continue
        fi
        file "$dir/$binary"
        file "$dir/$binary" | grep -Eq 'statically linked|static-pie linked' || {
            echo "$binary is not statically linked" >&2
            exit 1
        }
        if readelf --program-headers "$dir/$binary" | grep -q 'Requesting program interpreter'; then
            echo "$binary has a dynamic program interpreter" >&2
            exit 1
        fi
    done < <(
        cd "$dir"
        find . -maxdepth 1 -type f -perm /111 -printf '%P\n' | LC_ALL=C sort
    )

    (
        cd "$dir"
        sha256sum --check SHA256SUMS
    )
}

check_archive "$output_dir" main
# The extra archive must exist exactly when components.tsv gives it a tool.
if [[ -n $("$repo_root/scripts/components.sh" "$arch" extra) ]]; then
    check_archive "$output_dir-extra" extra
elif [[ -e $output_dir-extra ]]; then
    echo "$output_dir-extra exists, but components.tsv puts nothing in $arch's extra archive" >&2
    exit 1
fi

for binary in "${required_binaries[@]}"; do
    [[ -x $output_dir/$binary ]] || {
        echo "missing executable: $output_dir/$binary" >&2
        exit 1
    }
done
# Each extra tool listed above must be in the extra archive, which
# check_archive has already required wherever components.tsv gives it one.
if [[ -d $output_dir-extra ]]; then
    for binary in "${!extra_smoke[@]}"; do
        [[ -x $output_dir-extra/$binary ]] || {
            echo "missing executable: $output_dir-extra/$binary" >&2
            exit 1
        }
    done
fi

for nmap_data in \
    nmap-mac-prefixes \
    nmap-os-db \
    nmap-protocols \
    nmap-rpc \
    nmap-service-probes \
    nmap-services \
    nmap.dtd \
    nmap.xsl; do
    [[ -s $output_dir/share/nmap/$nmap_data ]] || {
        echo "missing Nmap runtime data: $nmap_data" >&2
        exit 1
    }
done

for testssl_data in testssl.sh etc/Mozilla.pem etc/ca_hashes.txt etc/cipher-mapping.txt \
    etc/client-simulation.txt etc/common-primes.txt etc/openssl.cnf etc/tls_data.txt; do
    [[ -s $output_dir/share/testssl/$testssl_data ]] || {
        echo "missing testssl.sh runtime data: $testssl_data" >&2
        exit 1
    }
done

# python3's standard library and the directory CPython takes as its
# installation's marker, on every target.
python_series=$(pinned_version python)
python_series=${python_series%.*}
for python_data in "lib/python${python_series/./}.zip" "lib/python$python_series/lib-dynload/README"; do
    [[ -s $output_dir-extra/$python_data ]] || {
        echo "missing python3 runtime data: $python_data" >&2
        exit 1
    }
done

# tcc's runtime beside it: its own headers and libtcc1.a, and musl's
# headers, start files, and libc.a.
if [[ $tcc_cpu != none ]]; then
    for tcc_data in libtcc1.a bt-exe.o bt-log.o include/stddef.h include/tccdefs.h \
        musl/include/stdio.h musl/lib/libc.a musl/lib/crt1.o musl/lib/crti.o musl/lib/crtn.o; do
        [[ -s $output_dir-extra/lib/tcc/$tcc_data ]] || {
            echo "missing tcc runtime data: lib/tcc/$tcc_data" >&2
            exit 1
        }
    done
elif [[ -e $output_dir-extra/tcc || -e $output_dir-extra/lib/tcc ]]; then
    echo "tcc is in $arch's extra archive, but architectures.tsv gives it no tcc cpu" >&2
    exit 1
fi

for link in hexdump grep awk sed; do
    [[ -L $output_dir/share/testssl/bin/$link && -x $output_dir/share/testssl/bin/$link ]] || {
        echo "missing testssl.sh BusyBox link: share/testssl/bin/$link" >&2
        exit 1
    }
done

for link in nc netcat dropbear dbclient dropbearkey dropbearconvert scp tunpipe \
    fsck.ext2 fsck.ext3 fsck.ext4 mkfs.ext4 \
    unzstd zstdcat unxz xzcat bunzip2 bzcat unpigz \
    modinfo lsmod insmod rmmod modprobe depmod ping6 traceroute6 \
    iptables-legacy iptables-legacy-save iptables-legacy-restore \
    ip6tables-legacy ip6tables-legacy-save ip6tables-legacy-restore \
    mount.nfs4 umount.nfs umount.nfs4 partclone.ext2 partclone.ext3 \
    partclone.ext4 partclone.vfat partclone.fat12 partclone.fat16 partclone.fat32; do
    [[ -L $output_dir/$link ]] || {
        echo "missing applet link: $output_dir/$link" >&2
        exit 1
    }
done
for link in par2create par2verify par2repair; do
    [[ -L $output_dir-extra/$link ]] || {
        echo "missing link: $output_dir-extra/$link" >&2
        exit 1
    }
done

# Every smoke command runs under a hard timeout, so one that hangs (as
# qemu-user's netlink emulation can make a program spin) fails the check
# instead of stalling it.
runner=(timeout --kill-after=10 120)
emulated=
if [[ ${SKIP_QEMU:-0} != 1 ]]; then
    if [[ $arch == x86_64 && $(uname -m) == x86_64 ]]; then
        :
    elif command -v "$qemu" >/dev/null 2>&1; then
        runner+=("$qemu")
        emulated=1
    elif command -v "${qemu}-static" >/dev/null 2>&1; then
        runner+=("${qemu}-static")
        emulated=1
    else
        echo "QEMU runner not found ($qemu); static inspection passed" >&2
        exit 1
    fi

    check_output() {
        local needle=$1
        shift
        local output
        if ! output=$("${runner[@]}" "$@" 2>&1); then
            echo "smoke check failed: $*" >&2
            return 1
        fi
        if [[ $output != *"$needle"* ]]; then
            echo "unexpected output from $*: $output" >&2
            return 1
        fi
    }

    "${runner[@]}" "$output_dir/busybox" true
    "${runner[@]}" "$output_dir/busybox" netcat --help >/dev/null 2>&1
    check_output WITH_OPENSSL "$output_dir/socat" -V
    check_output Dropbear "$output_dir/dropbearmulti" dropbear -V
    check_output "usage: tunpipe" "$output_dir/dropbearmulti" tunpipe -h
    check_output "usage: tunpipe" "$output_dir/tunpipe-standalone" -h
    check_output iproute2 "$output_dir/ip" -Version
    check_output iproute2 "$output_dir/ss" -V
    check_output "bridge utility" "$output_dir/bridge" -V
    check_output iproute2 "$output_dir/tc" -V
    check_output wireguard-tools "$output_dir/wg" --version
    # nft opens a NETLINK_NETFILTER socket in nft_ctx_new() before it parses any
    # argument, and qemu-user cannot emulate AF_NETLINK — so nft aborts at
    # startup under emulation, even for --version (ip/ss/tc read --version
    # first, which is why they smoke-test fine). Runtime-check nft only when
    # running natively; every arch still gets the static-ELF checks above.
    if [[ -z $emulated ]]; then
        check_output nftables "$output_dir/nft" --version
    fi
    check_output OpenSSL "$output_dir/openssl" version
    check_output tcpdump "$output_dir/tcpdump" --version
    check_output "libssh2/$(pinned_version libssh2)" "$output_dir/curl" --version
    check_output " scp sftp " "$output_dir/curl" --version
    check_output iperf "$output_dir/iperf3" --version
    check_output ethtool "$output_dir/ethtool" --version
    check_output strace "$output_dir/strace" --version
    check_output jq "$output_dir/jq" --version
    check_output drill "$output_dir/drill" -v
    check_output mtr "$output_dir/mtr" --version
    check_output i2cdetect "$output_dir/i2cdetect" -V
    check_output Nmap "$output_dir/nmap" --version
    check_output Ncat "$output_dir/ncat" --version
    check_output rsync "$output_dir/rsync" --version
    check_output version "$output_dir/lsof" -v
    check_output e2fsck "$output_dir/e2fsck" -V
    check_output dumpe2fs "$output_dir/dumpe2fs" -V
    check_output mke2fs "$output_dir/mke2fs" -V
    check_output smartctl "$output_dir/smartctl" --version
    check_output "nvme version" "$output_dir/nvme" version
    # pppd reads /etc/ppp/options before any argument and, unless root,
    # stops when it is missing. Either message proves it started.
    pppd_output=$("${runner[@]}" "$output_dir/pppd" --version 2>&1) || true
    [[ $pppd_output == *"pppd version"* || $pppd_output == *"/etc/ppp/options"* ]] || {
        echo "unexpected output from pppd --version: $pppd_output" >&2
        exit 1
    }
    check_output picocom "$output_dir/picocom" --help
    check_output lrzsz "$output_dir/sz" --version
    check_output lrzsz "$output_dir/rz" --version
    check_output gdbserver "$output_dir/gdbserver" --version
    check_output util-linux "$output_dir/nsenter" --version
    check_output util-linux "$output_dir/unshare" --version
    check_output util-linux "$output_dir/lsns" --version
    check_output util-linux "$output_dir/setpriv" --version
    check_output util-linux "$output_dir/findmnt" --version
    for program in lsblk blkid sfdisk losetup mount umount dmesg; do
        check_output util-linux "$output_dir/$program" --version
    done
    # sftp-server has no version flag; -Q lists the requests it serves. It
    # looks up the calling user first, so a uid without a passwd entry (a
    # container's --user) stops it with "No user found"; that also proves it
    # started.
    sftp_output=$("${runner[@]}" "$output_dir/sftp-server" -Q requests 2>&1) || true
    [[ $sftp_output == *posix-rename* || $sftp_output == *"No user found for uid"* ]] || {
        echo "unexpected output from sftp-server -Q requests: $sftp_output" >&2
        exit 1
    }
    # Like nft, conntrack opens a NETLINK_NETFILTER socket before it parses
    # any argument, which qemu-user cannot emulate. Under emulation its
    # "Can't open handler" error proves it started; natively, --version runs.
    if [[ -z $emulated ]]; then
        check_output conntrack-tools "$output_dir/conntrack" --version
    else
        conntrack_output=$("${runner[@]}" "$output_dir/conntrack" --version 2>&1) || true
        [[ $conntrack_output == *"(conntrack-tools): Can't open handler"* ]] || {
            echo "unexpected output from conntrack --version: $conntrack_output" >&2
            exit 1
        }
    fi
    check_output "ipmitool version" "$output_dir/ipmitool" -V
    check_output "iw version" "$output_dir/iw" --version
    for program in flash_erase flashcp nanddump nandwrite mtdinfo \
        ubiattach ubidetach ubinfo ubimkvol ubirmvol ubiupdatevol; do
        check_output mtd-utils "$output_dir/$program" --version
    done
    check_output "v$(pinned_version zstd)" "$output_dir/zstd" -V
    check_output "xz (XZ Utils) $(pinned_version xz)" "$output_dir/xz" --version
    check_output "Version $(pinned_version bzip2)" "$output_dir/bzip2" --help
    check_output "pigz $(pinned_version pigz)" "$output_dir/pigz" --version
    check_output "pv $(pinned_version pv)" "$output_dir/pv" --version
    check_output "R$(pinned_version mbuffer)" "$output_dir/mbuffer" --version
    # Each names the compression libraries it linked.
    libraries="zlib/$(pinned_version zlib) liblzma/$(pinned_version xz)"
    libraries+=" bz2lib/$(pinned_version bzip2) libzstd/$(pinned_version zstd)"
    check_output "$libraries" "$output_dir/bsdtar" --version
    check_output "$libraries" "$output_dir/bsdcpio" --version
    # Round trips through each compressor, bsdtar's filters, pv, and
    # mbuffer: the codecs' byte order and word size are what differ by arch.
    # The host's xz, bzip2, and gzip also decode the target's output, which
    # catches a fault shared by the target's encoder and decoder.
    scratch=$(mktemp -d)
    trap 'rm -rf "$scratch"' EXIT
    sample=$output_dir/sources.lock
    declare -A host_decoder=([xz]=xz [bzip2]=bzip2 [pigz]=gzip)
    failed() { echo "$1 round trip failed" >&2; exit 1; }
    for program in zstd xz bzip2 pigz; do
        "${runner[@]}" "$output_dir/$program" -c <"$sample" >"$scratch/packed" ||
            failed "$program"
        "${runner[@]}" "$output_dir/$program" -dc <"$scratch/packed" >"$scratch/unpacked" ||
            failed "$program"
        cmp -s "$scratch/unpacked" "$sample" || failed "$program"
        [[ -z ${host_decoder[$program]:-} ]] && continue
        "${host_decoder[$program]}" -dc <"$scratch/packed" >"$scratch/unpacked" ||
            failed "host ${host_decoder[$program]} of $program"
        cmp -s "$scratch/unpacked" "$sample" || failed "host ${host_decoder[$program]} of $program"
    done
    for filter in --zstd --xz --bzip2 --gzip; do
        "${runner[@]}" "$output_dir/bsdtar" -c "$filter" -f "$scratch/packed" \
            -C "$output_dir" sources.lock || failed "bsdtar $filter"
        "${runner[@]}" "$output_dir/bsdtar" -xOf "$scratch/packed" >"$scratch/unpacked" ||
            failed "bsdtar $filter"
        cmp -s "$scratch/unpacked" "$sample" || failed "bsdtar $filter"
    done
    "${runner[@]}" "$output_dir/pv" -q <"$sample" |
        "${runner[@]}" "$output_dir/mbuffer" -q -m 1M >"$scratch/piped" || failed "pv | mbuffer"
    cmp -s "$scratch/piped" "$sample" || failed "pv | mbuffer"
    check_output "kmod version $(pinned_version kmod)" "$output_dir/kmod" --version
    check_output "+ZSTD +XZ +ZLIB" "$output_dir/kmod" --version
    # modinfo reads a minimal module (an x86-64 ELF relocatable with only a
    # .modinfo section) plain and compressed each way libkmod decodes:
    # libkmod's ELF parsing and the linked decompressors on every byte
    # order. zstd compresses from a file, as kbuild does, so the frame
    # records the size libkmod requires.
    python3 -I - "$scratch/smoke.ko" <<'PY'
import struct
import sys

info = b"license=GPL\0description=statics smoke\0"
names = b"\0.modinfo\0.shstrtab\0"
section_offset = (64 + len(info) + len(names) + 7) & ~7
header = b"\x7fELF\x02\x01\x01" + bytes(9) + struct.pack(
    "<HHIQQQIHHHHHH", 1, 62, 1, 0, 0, section_offset, 0, 64, 0, 0, 64, 3, 2
)
body = (header + info + names).ljust(section_offset, b"\0")


def section(name, kind, offset, size):
    return struct.pack("<IIQQQQIIQQ", name, kind, 0, 0, offset, size, 0, 0, 1, 0)


body += section(0, 0, 0, 0)
body += section(1, 1, 64, len(info))
body += section(10, 3, 64 + len(info), len(names))
with open(sys.argv[1], "wb") as module:
    module.write(body)
PY
    xz -c "$scratch/smoke.ko" >"$scratch/smoke.ko.xz"
    gzip -c "$scratch/smoke.ko" >"$scratch/smoke.ko.gz"
    "${runner[@]}" "$output_dir/zstd" -q -o "$scratch/smoke.ko.zst" "$scratch/smoke.ko" || {
        echo "zstd could not compress the test module" >&2
        exit 1
    }
    for module in smoke.ko smoke.ko.xz smoke.ko.gz smoke.ko.zst; do
        check_output "statics smoke" "$output_dir/modinfo" -F description "$scratch/$module"
    done
    check_output "kexec-tools $(pinned_version kexec-tools)" "$output_dir/kexec" --version
    check_output "bpftool v$(pinned_version bpftool)" "$output_dir/bpftool" version
    for program in ping arping tracepath; do
        check_output "$program from iputils $(pinned_version iputils)" "$output_dir/$program" -V
    done
    check_output "version $(pinned_version traceroute)" "$output_dir/traceroute" -V
    for program in ndisc6 rdisc6 rltraceroute6; do
        check_output " $(pinned_version ndisc6) " "$output_dir/$program" -V
    done
    check_output "Usage:" "$output_dir/tcptraceroute6" -h
    for program in nstat devlink rdma; do
        check_output "iproute2-$(pinned_version iproute2)" "$output_dir/$program" -V
    done
    check_output "$(pinned_version lldpd)" "$output_dir/lldpd" -v
    check_output "$(pinned_version lldpd)" "$output_dir/lldpcli" -v
    for program in iptables ip6tables; do
        check_output "v$(pinned_version iptables) (legacy)" "$output_dir/$program-legacy" -V
    done
    check_output "ebtables v$(pinned_version ebtables) (legacy)" "$output_dir/ebtables-legacy" -V
    # ipset prints its version, then asks the kernel for its protocol over
    # netlink, and arptables opens its table before reading -V; both fail
    # unprivileged or under qemu-user after printing their name and version.
    for program in "ipset v$(pinned_version ipset)|ipset|version" \
        "arptables v$(pinned_version arptables)|arptables-legacy|-V"; do
        IFS='|' read -r needle binary argument <<<"$program"
        program_output=$("${runner[@]}" "$output_dir/$binary" "$argument" 2>&1) || true
        [[ $program_output == *"$needle"* ]] || {
            echo "unexpected output from $binary $argument: $program_output" >&2
            exit 1
        }
    done
    check_output "V$(pinned_version ngrep)" "$output_dir/ngrep" -V
    # hping3 reports upstream's 2004 version string, not Debian's.
    check_output "hping3 version 3.0.0-alpha-2" "$output_dir/hping3" -v
    check_output "iftop: display bandwidth usage" "$output_dir/iftop" -h
    check_output "version $(pinned_version nethogs)" "$output_dir/nethogs" -V
    for program in tcpprep tcprewrite; do
        check_output "$program version: $(pinned_version tcpreplay)" "$output_dir/$program" -V
    done
    # tcpreplay lists every interface (over netlink, then an ethtool ioctl
    # each) before it reads any option, even -V. qemu-user lacks that ioctl,
    # and on big-endian targets its netlink emulation leaves musl's
    # interface listing spinning, so tcpreplay runs natively only; under
    # emulation tcpprep and tcprewrite, built from the same tree and
    # libraries, are exercised below.
    if [[ -z $emulated ]]; then
        check_output "tcpreplay version: $(pinned_version tcpreplay)" "$output_dir/tcpreplay" -V
    fi
    # A capture of a DHCPDISCOVER and a TCP segment carrying a marker:
    # dhcpdump and ngrep decode it, tcpprep classifies it, tcprewrite
    # rewrites the TCP destination and its checksum, and tcpdump confirms
    # the checksum. The parsers' byte order is what differs by arch.
    python3 -I - "$scratch/smoke.pcap" <<'PY'
import struct
import sys


def checksum(data):
    data += b"\0" * (len(data) % 2)
    total = sum(struct.unpack(f"!{len(data) // 2}H", data))
    total = (total >> 16) + (total & 0xFFFF)
    return ~(total + (total >> 16)) & 0xFFFF


def ipv4(protocol, source, destination, payload):
    header = struct.pack(
        "!BBHHHBBH4s4s", 0x45, 0, 20 + len(payload), 1, 0, 64, protocol, 0,
        bytes(source), bytes(destination),
    )
    header = header[:10] + struct.pack("!H", checksum(header)) + header[12:]
    return header + payload


def frame(destination, payload):
    return destination + bytes.fromhex("020000000001") + b"\x08\x00" + payload


bootp = struct.pack(
    "!BBBBIHH4s4s4s4s16s64s128s", 1, 1, 6, 0, 0x5EED, 0, 0x8000,
    bytes(4), bytes(4), bytes(4), bytes(4),
    bytes.fromhex("020000000001").ljust(16, b"\0"), bytes(64), bytes(128),
)
bootp += bytes.fromhex("63825363") + b"\x35\x01\x01\xff"
dhcp = ipv4(17, [0, 0, 0, 0], [255, 255, 255, 255],
            struct.pack("!HHHH", 68, 67, 8 + len(bootp), 0) + bootp)
# The TCP checksum is left zero for tcprewrite --fixcsum to fill in.
tcp = ipv4(6, [10, 0, 0, 1], [10, 0, 0, 2],
           struct.pack("!HHIIBBHHH", 40000, 80, 1, 0, 0x50, 0x18, 1024, 0, 0)
           + b"statics-smoke")
packets = [frame(b"\xff" * 6, dhcp), frame(bytes.fromhex("020000000002"), tcp)]
with open(sys.argv[1], "wb") as capture:
    capture.write(struct.pack("<IHHiIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, 1))
    for number, packet in enumerate(packets):
        capture.write(struct.pack("<IIII", number + 1, 0, len(packet), len(packet)))
        capture.write(packet)
PY
    check_output "1 (DHCPDISCOVER)" "$output_dir/dhcpdump" -r "$scratch/smoke.pcap"
    # Without -d, ngrep lists the interfaces even to read a file, which
    # qemu-user cannot emulate; with -I the device is not opened.
    check_output "10.0.0.1:40000 -> 10.0.0.2:80" "$output_dir/ngrep" -q -d lo -I "$scratch/smoke.pcap" statics-smoke
    "${runner[@]}" "$output_dir/tcpprep" --auto=bridge --pcap="$scratch/smoke.pcap" \
        --cachefile="$scratch/smoke.cache" || failed "tcpprep"
    "${runner[@]}" "$output_dir/tcprewrite" --infile="$scratch/smoke.pcap" \
        --outfile="$scratch/rewritten.pcap" --cachefile="$scratch/smoke.cache" \
        --dstipmap=10.0.0.2/32:10.0.0.9/32 --fixcsum || failed "tcprewrite"
    check_output "10.0.0.1:40000 -> 10.0.0.9:80" "$output_dir/ngrep" -q -d lo -I "$scratch/rewritten.pcap" statics-smoke
    check_output "cksum 0x01d2 (correct)" "$output_dir/tcpdump" -vvnr "$scratch/rewritten.pcap" tcp
    check_output "tmux $(pinned_version tmux)" "$output_dir/tmux" -V
    # A detached session runs a command in its pane; capture-pane reads the
    # pane back through the server: the client, server, pty, and libevent.
    # shellcheck disable=SC2016  # expanded by the pane's shell
    "${runner[@]}" "$output_dir/tmux" -S "$scratch/tmux" -f /dev/null \
        new-session -d -x 80 -y 24 /bin/sh -c 'echo statics-$((6 * 7)); sleep 30' ||
        failed "tmux new-session"
    tmux_output=
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        tmux_output=$("${runner[@]}" "$output_dir/tmux" -S "$scratch/tmux" capture-pane -p) ||
            failed "tmux capture-pane"
        [[ $tmux_output == *statics-42* ]] && break
        sleep 1
    done
    "${runner[@]}" "$output_dir/tmux" -S "$scratch/tmux" kill-server || true
    [[ $tmux_output == *statics-42* ]] || failed "tmux session"
    # python3 finds its standard library in lib/pythonXY.zip with nothing set
    # in the environment and nothing on stderr, then uses each library it
    # links: zlib, bz2, lzma, zstd, OpenSSL (a hash through hashlib and a
    # TLS context), SQLite, and expat; packs integers and floats; and runs
    # a host command.
    python_output=$(env -i PATH="$PATH" "${runner[@]}" "$output_dir-extra/python3" -c '
import bz2, hashlib, json, lzma, sqlite3, ssl, struct, subprocess, sys, zlib
import xml.etree.ElementTree as ET
from compression import zstd
data = b"statics" * 1000
for codec in (zlib, bz2, lzma, zstd):
    assert codec.decompress(codec.compress(data)) == data, codec
assert hashlib.new("sha256", b"x").hexdigest().startswith("2d711642")
assert ssl.create_default_context().minimum_version >= ssl.TLSVersion.TLSv1_2
db = sqlite3.connect(":memory:")
db.execute("create virtual table f using fts5(x)")
db.execute("insert into f values (?)", ("static musl kit",))
assert db.execute("select x from f where f match ?", ("musl",)).fetchone()
assert ET.fromstring("<a><b>42</b></a>").findtext("b") == "42"
assert struct.unpack("<dq", struct.pack("<dq", 0.1, -2)) == (0.1, -2)
assert repr(0.1 + 0.2) == "0.30000000000000004"
out = subprocess.run(["/bin/sh", "-c", "echo sub"], capture_output=True).stdout
# Bytecode from the zip, not a recompile of the source beside it.
assert struct.__spec__.origin.endswith(".pyc"), struct.__spec__.origin
print(json.dumps({"ok": out.decode().strip(), "hash": sys.hash_info.algorithm,
                  "zip": struct.__spec__.origin.split("/")[-2]}))
' 2>&1) || { echo "$python_output" >&2; failed "python3"; }
    [[ $python_output == "{\"ok\": \"sub\", \"hash\": \"siphash13\", \"zip\": \"python${python_series/./}.zip\"}" ]] || {
        echo "unexpected output from python3: $python_output" >&2
        exit 1
    }
    # binutils on a source every target's assembler accepts, a word of
    # text and a labelled string: as assembles it, nm lists the symbol,
    # readelf reports the word size, byte order, and machine the tools
    # themselves are built for, ar archives the object, ld links it
    # relocatably and then finally, objcopy extracts the section, strings
    # and objdump find the text, objdump disassembles, and strip removes
    # the symbols and nothing else.
    binutils=$output_dir-extra
    mkdir "$scratch/binutils"
    printf '%s\n' '	.text' '	.globl _start' '_start:' '	.long 0' \
        '	.data' '	.globl statics_marker' 'statics_marker:' '	.ascii "statics-binutils"' \
        >"$scratch/binutils/marker.s"
    # Each tool reports exactly the pinned release, not a dated snapshot.
    for binary in ar as ld nm objcopy objdump readelf strings strip; do
        version=$("${runner[@]}" "$binutils/$binary" --version) || failed "$binary --version"
        # The first line; not `| head -n 1`, which can end the pipe early
        # and fail the command under pipefail.
        version=${version%%$'\n'*}
        [[ $version == *"(GNU Binutils) $(pinned_version binutils)" ]] || {
            echo "unexpected version from $binary: $version" >&2
            exit 1
        }
    done
    "${runner[@]}" "$binutils/as" -o "$scratch/binutils/marker.o" "$scratch/binutils/marker.s" ||
        failed "as"
    check_output "D statics_marker" "$binutils/nm" "$scratch/binutils/marker.o"
    # Word size, byte order, and machine: mips and mipsel differ only in
    # the second.
    identity() { "${runner[@]}" "$binutils/readelf" -h "$1" | grep -E '^ +(Class|Data|Machine):'; }
    machine=$(identity "$binutils/as") || failed "readelf"
    [[ $(wc -l <<<"$machine") -eq 3 && $(identity "$scratch/binutils/marker.o") == "$machine" ]] ||
        failed "readelf: as did not assemble for its own target, which"
    "${runner[@]}" "$binutils/ar" rcs "$scratch/binutils/libmarker.a" "$scratch/binutils/marker.o" ||
        failed "ar"
    check_output marker.o "$binutils/ar" t "$scratch/binutils/libmarker.a"
    "${runner[@]}" "$binutils/ld" -r -o "$scratch/binutils/linked.o" "$scratch/binutils/marker.o" ||
        failed "ld -r"
    "${runner[@]}" "$binutils/objcopy" -O binary -j .data "$scratch/binutils/linked.o" \
        "$scratch/binutils/data.bin" || failed "objcopy"
    [[ $(<"$scratch/binutils/data.bin") == statics-binutils ]] || failed "objcopy"
    check_output statics-binutils "$binutils/strings" "$scratch/binutils/linked.o"
    check_output "statics-binutils" "$binutils/objdump" -s -j .data "$scratch/binutils/linked.o"
    # A final link with the default emulation, and the disassembler on it.
    # -e because the default entry symbol is not _start everywhere (MIPS:
    # __start). The object is what objdump disassembles: in the linked
    # file MIPS labels the same address _ftext.
    "${runner[@]}" "$binutils/ld" -e _start -o "$scratch/binutils/marker.elf" \
        "$scratch/binutils/marker.o" || failed "ld"
    [[ $(identity "$scratch/binutils/marker.elf") == "$machine" ]] || failed "ld emulation"
    check_output "<_start>:" "$binutils/objdump" -d "$scratch/binutils/marker.o"
    "${runner[@]}" "$binutils/strip" "$scratch/binutils/marker.elf" || failed "strip"
    # Stripped, the file is still that executable, text intact, without
    # its symbols.
    [[ $(identity "$scratch/binutils/marker.elf") == "$machine" ]] || failed "strip"
    check_output statics-binutils "$binutils/strings" "$scratch/binutils/marker.elf"
    check_output "no symbols" "$binutils/nm" "$scratch/binutils/marker.elf"
    if [[ $tcc_cpu != none ]]; then
        # tcc finds lib/tcc beside itself with nothing set, compiles a
        # program that needs libtcc1 (64-bit division on the 32-bit
        # targets), musl's printf and strdup, and libm, and links it
        # statically; the program runs. The same object then links with
        # binutils' ld against the same musl, and objdump disassembles the
        # result. -bt reports a fault's source line, and -run is refused.
        tcc=$output_dir-extra/tcc
        musl=$output_dir-extra/lib/tcc/musl/lib
        mkdir "$scratch/tcc"
        cat >"$scratch/tcc/hello.c" <<'C'
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc, char **argv)
{
    uint64_t big = 1000000007ULL * (uint64_t)(argc + 41);
    char *copy = strdup("statics");
    (void)argv;
    printf("%s %llu %llu %.4f\n", copy, (unsigned long long)(big / 6),
           (unsigned long long)(big % 1000), sqrt((double)(argc + 1)));
    free(copy);
    return 0;
}
C
        echo 'int main(void) { int *p = 0; return *p; }' >"$scratch/tcc/fault.c"
        env -i PATH="$PATH" "${runner[@]}" "$tcc" -Wall -Werror -o "$scratch/tcc/hello" \
            "$scratch/tcc/hello.c" || failed "tcc"
        file "$scratch/tcc/hello" | grep -q 'statically linked' || failed "tcc static link"
        check_output "statics 7333333384 308 2.0000" "$scratch/tcc/hello" a b
        "${runner[@]}" "$tcc" -c -o "$scratch/tcc/hello.o" "$scratch/tcc/hello.c" ||
            failed "tcc -c"
        "${runner[@]}" "$binutils/ld" -static -z noexecstack -o "$scratch/tcc/hello-ld" \
            "$musl/crt1.o" "$musl/crti.o" "$scratch/tcc/hello.o" "$musl/libc.a" \
            "$output_dir-extra/lib/tcc/libtcc1.a" "$musl/libc.a" "$musl/crtn.o" ||
            failed "ld with tcc's musl"
        check_output "statics 7333333384 308 2.0000" "$scratch/tcc/hello-ld" a b
        check_output "<main>:" "$binutils/objdump" -d "$scratch/tcc/hello-ld"
        "${runner[@]}" "$tcc" -bt -o "$scratch/tcc/fault" "$scratch/tcc/fault.c" ||
            failed "tcc -bt"
        tcc_output=$("${runner[@]}" "$scratch/tcc/fault" 2>&1) && failed "tcc -bt fault"
        [[ $tcc_output == *"fault.c:1: at main: RUNTIME ERROR"* ]] || {
            echo "unexpected output from a tcc -bt program: $tcc_output" >&2
            exit 1
        }
        tcc_output=$("${runner[@]}" "$tcc" -run "$scratch/tcc/hello.c" 2>&1) && failed "tcc -run refusal"
        [[ $tcc_output == *"-run is not available in this static tcc"* ]] || {
            echo "unexpected output from tcc -run: $tcc_output" >&2
            exit 1
        }
    fi
    if [[ $go_env != none ]]; then
        # The Go tools beyond their versions: caddy adapts a Caddyfile to
        # JSON, yq converts YAML, and age encrypts to a fresh key and
        # decrypts on every byte order. None opens a socket.
        printf ':8080 {\n\treverse_proxy 127.0.0.1:9000\n}\n' >"$scratch/Caddyfile"
        check_output '"handler":"reverse_proxy","upstreams":[{"dial":"127.0.0.1:9000"}]' \
            "$output_dir-extra/caddy" adapt --config "$scratch/Caddyfile" --adapter caddyfile
        check_output '{"b":42}' "$output_dir-extra/yq" -o=json -I=0 .a <<<'a: {b: 42}'
        "${runner[@]}" "$output_dir-extra/age-keygen" -o "$scratch/age.key" 2>/dev/null ||
            failed "age-keygen"
        age_recipient=$("${runner[@]}" "$output_dir-extra/age-keygen" -y "$scratch/age.key") ||
            failed "age-keygen -y"
        "${runner[@]}" "$output_dir-extra/age" -r "$age_recipient" -o "$scratch/age.out" "$sample" ||
            failed "age encrypt"
        "${runner[@]}" "$output_dir-extra/age" -d -i "$scratch/age.key" "$scratch/age.out" |
            cmp -s - "$sample" || failed "age"
    fi
    # A static key, then OpenVPN's own loopback encrypt and decrypt with
    # it: OpenSSL's ciphers and OpenVPN's packet code on every byte order.
    "${runner[@]}" "$output_dir-extra/openvpn" --genkey secret "$scratch/static.key" >/dev/null ||
        failed "openvpn --genkey"
    check_output "self-test mode SUCCEEDED" "$output_dir-extra/openvpn" --test-crypto --secret "$scratch/static.key" \
        --cipher AES-256-CBC --verb 1
    # microsocks has no version flag; its usage proves it started.
    microsocks_output=$("${runner[@]}" "$output_dir/microsocks" -h 2>&1) || true
    [[ $microsocks_output == *"MicroSocks SOCKS5 Server"* ]] || {
        echo "unexpected output from microsocks -h: $microsocks_output" >&2
        exit 1
    }
    check_output "tinyproxy $(pinned_version tinyproxy)" "$output_dir/tinyproxy" -v
    check_output "Dnsmasq version $(pinned_version dnsmasq)" "$output_dir/dnsmasq" --version
    printf 'port=0\ndhcp-range=192.0.2.10,192.0.2.20,1h\nenable-tftp\ntftp-root=/tmp\n' \
        >"$scratch/dnsmasq.conf"
    check_output "syntax check OK" "$output_dir/dnsmasq" --test --conf-file="$scratch/dnsmasq.conf"
    check_output "version $(pinned_version ser2net)" "$output_dir/ser2net" -v
    # ser2net shares one end of a socat pty pair on a loopback port; two
    # connections in turn each read a line written to the other end, which
    # catches a port that never finishes closing after the first client.
    # Natively only: it needs real ptys and TCP between the two programs.
    if [[ -z $emulated ]]; then
        "${runner[@]}" "$output_dir/socat" pty,link="$scratch/ttyA",raw,echo=0 \
            pty,link="$scratch/ttyB",raw,echo=0 &
        socat_pid=$!
        for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -e $scratch/ttyB ]] && break; sleep 0.5; done
        exec {tty_hold}<>"$scratch/ttyA"
        ser2net_port=$((20000 + $$ % 20000))
        printf 'connection: &smoke\n  accepter: tcp,127.0.0.1,%s\n  connector: serialdev,%s,115200n81,local\n' \
            "$ser2net_port" "$scratch/ttyA" >"$scratch/ser2net.yaml"
        "${runner[@]}" "$output_dir/ser2net" -n -c "$scratch/ser2net.yaml" -P "$scratch/ser2net.pid" &
        ser2net_pid=$!
        sleep 1
        for attempt in 1 2; do
            (sleep 1; printf 'statics-serial-%s\n' "$attempt" >"$scratch/ttyB") &
            ser2net_output=$(sleep 3 | "${runner[@]}" "$output_dir/socat" -t 3 - \
                "tcp:127.0.0.1:$ser2net_port" 2>&1) || true
            [[ $ser2net_output == *statics-serial-$attempt* ]] || {
                kill "$ser2net_pid" "$socat_pid" 2>/dev/null
                failed "ser2net connection $attempt"
            }
            sleep 1
        done
        kill "$ser2net_pid" "$socat_pid" 2>/dev/null || true
        exec {tty_hold}<&-
    fi
    check_output "version $(pinned_version bash)" "$output_dir/bash" --version
    # shellcheck disable=SC2016  # expanded by the bash under test
    check_output "statics-42" "$output_dir/bash" -c \
        'a=(statics 42); [[ ${a[1]} =~ ^4 ]] && cat <(printf "%s-%s\n" "${a[@]}")'
    check_output "$(pinned_version sqlite) " "$output_dir/sqlite3" --version
    # A database file written, then read back by a second process: JSON,
    # math, and an FTS5 index.
    "${runner[@]}" "$output_dir/sqlite3" -noinit "$scratch/smoke.db" \
        "create table t(a, b); insert into t values('statics', json_extract('{\"n\":42}', '\$.n')); create virtual table f using fts5(x); insert into f values('static musl kit');" ||
        failed "sqlite3 create"
    check_output "statics|42|4.0|static musl kit" "$output_dir/sqlite3" -noinit "$scratch/smoke.db" \
        "select a, b, sqrt(16), (select x from f where f match 'musl') from t;"
    check_output "$(pinned_version quickjs)" "$output_dir/qjs" --version
    check_output 'statics-42 18446744073709551616 {"a":true}' "$output_dir/qjs" -e \
        'console.log("statics-" + [1, 2, 3].map(x => x * 14).at(-1), 2n ** 64n, JSON.stringify({a: /x/v.test("x")}))'
    # The scripts upstream ships as little-endian bytecode are compiled from
    # embedded source instead (the quickjs patch), on either byte order:
    # three builtins, the REPL, and the loader behind -c.
    check_output 'function [[1,3],[2,4]] [{"a":1,"b":2}]' "$output_dir/qjs" -e \
        'console.log(typeof Array.fromAsync, JSON.stringify([...Iterator.zip([[1, 2], [3, 4]])]), JSON.stringify([...Iterator.zipKeyed({a: [1], b: [2]})]))'
    check_output "repl 42" "$output_dir/qjs" --std -i <<<'console.log("repl", 6 * 7); std.exit(0)'
    echo 'console.log("standalone", 6 * 7)' >"$scratch/smoke.js"
    "${runner[@]}" "$output_dir/qjs" -c "$scratch/smoke.js" -o "$scratch/smoke-js" ||
        failed "qjs -c"
    check_output "standalone 42" "$scratch/smoke-js"
    check_output "Lua $(pinned_version lua)" "$output_dir/lua" -v
    # pcall catches the error through setjmp and longjmp.
    check_output "statics-42 false" "$output_dir/lua" -E -e \
        'print(("statics-%d %s"):format(6 * 7, tostring(pcall(error, "x"))))'
    check_output "htop $(pinned_version htop)" "$output_dir/htop" --version
    check_output "GNU Make $(pinned_version make)" "$output_dir/make" --version
    # A make function, in a recipe that needs /bin/sh (the `;`).
    check_output "statics-3" "$output_dir/make" -f - <<<$'all:\n\t@echo statics-$(words a b c); :'
    # testssl.sh runs the bundled openssl and BusyBox applets, which under
    # emulation only binfmt_misc could start, so natively only; it is the
    # same script on every target, and bash is checked above.
    if [[ -z $emulated ]]; then
        check_output "testssl.sh version $(pinned_version testssl.sh)" env COLOR=0 "$output_dir/testssl.sh" --version
    fi
    # mount.cifs prints its version only to root; otherwise it says why
    # user mounts are unsupported, which also proves it started.
    cifs_output=$("${runner[@]}" "$output_dir/mount.cifs" -V 2>&1) || true
    [[ $cifs_output == *"mount.cifs version: $(pinned_version cifs-utils)"* ||
        $cifs_output == *"not installed setuid root"* ]] || {
        echo "unexpected output from mount.cifs -V: $cifs_output" >&2
        exit 1
    }
    # nfs-utils 3.2.1 still reports the 3.1.1 of its configure.ac.
    check_output "(linux nfs-utils " "$output_dir/mount.nfs" -V
    check_output "showmount for " "$output_dir/showmount" -v
    # udpcast has no version option; its usage proves each started.
    for program in udp-sender udp-receiver; do
        program_output=$("${runner[@]}" "$output_dir/$program" --statics-usage 2>&1) || true
        [[ $program_output == *"[--file file]"* ]] || {
            echo "unexpected output from $program: $program_output" >&2
            exit 1
        }
    done
    # --version runs xxhsum's known-answer self-test of every algorithm.
    check_output "xxhsum $(pinned_version xxhash)" "$output_dir/xxhsum" --version
    # partclone clones an ext4 image made by the bundled mke2fs, checks
    # the image, and restores it to a new raw file, which must match: the
    # image format's byte order and libext2fs on every target.
    truncate -s 8M "$scratch/ext.img"
    "${runner[@]}" "$output_dir/mke2fs" -q -F -t ext4 -d "$output_dir/licenses" "$scratch/ext.img" ||
        failed "mke2fs for partclone"
    for program in partclone.extfs partclone.restore partclone.info; do
        check_output "Partclone : v$(pinned_version partclone)" "$output_dir/$program" -v
    done
    # With CRC32 (the default) and XXH64 checksums.
    for mode in 1 2; do
        rm -f "$scratch/ext.pcl" "$scratch/restored.img"
        "${runner[@]}" "$output_dir/partclone.extfs" -q -c -a "$mode" -s "$scratch/ext.img" \
            -o "$scratch/ext.pcl" -L "$scratch/partclone.log" >/dev/null 2>&1 ||
            failed "partclone.extfs clone"
        "${runner[@]}" "$output_dir/partclone.chkimg" -s "$scratch/ext.pcl" \
            -L "$scratch/partclone.log" >/dev/null 2>&1 || failed "partclone.chkimg"
        "${runner[@]}" "$output_dir/partclone.restore" -q -W -s "$scratch/ext.pcl" \
            -o "$scratch/restored.img" -L "$scratch/partclone.log" >/dev/null 2>&1 ||
            failed "partclone.restore"
        cmp -s "$scratch/ext.img" "$scratch/restored.img" || failed "partclone"
    done
    if [[ $go_env != none ]]; then
        check_output "wireguard-go v" "$output_dir/wireguard-go" --version
    fi
    # par2 creates recovery data for a file, then repairs damage to it:
    # its Reed-Solomon and MD5 code on every byte order.
    mkdir "$scratch/par2"
    cp "$sample" "$scratch/par2/data"
    "${runner[@]}" "$output_dir-extra/par2" create -q -q -r20 -n1 \
        "$scratch/par2/data.par2" "$scratch/par2/data" || failed "par2 create"
    printf 'statics' | dd of="$scratch/par2/data" bs=1 seek=100 conv=notrunc 2>/dev/null
    "${runner[@]}" "$output_dir-extra/par2" repair -q -q "$scratch/par2/data.par2" ||
        failed "par2 repair"
    cmp -s "$scratch/par2/data" "$sample" || failed "par2"
    # lftp mirrors a directory through its file: protocol.
    "${runner[@]}" "$output_dir-extra/lftp" -c \
        "open file:$output_dir; mirror licenses $scratch/lftp-mirror" || failed "lftp mirror"
    diff -r "$output_dir/licenses" "$scratch/lftp-mirror" >/dev/null || failed "lftp mirror"
    if [[ -d $output_dir-extra ]]; then
        while IFS= read -r binary; do
            [[ -n ${extra_smoke[$binary]:-} ]] || {
                echo "no smoke check in verify.sh for extra executable $binary" >&2
                exit 1
            }
            IFS='|' read -r needle arguments <<<"${extra_smoke[$binary]}"
            # shellcheck disable=SC2086  # arguments is a word list
            check_output "$needle" "$output_dir-extra/$binary" $arguments
        done < <(
            cd "$output_dir-extra"
            find . -maxdepth 1 -type f -perm /111 -printf '%P\n' | LC_ALL=C sort
        )
    fi
fi

echo "verified $arch"
