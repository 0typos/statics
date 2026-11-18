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
IFS='|' read -r _ _ _ qemu _ go_env <<<"$record"

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
)
# Go tools exist only where architectures.tsv gives a Go environment.
if [[ $go_env != none ]]; then
    required_binaries+=(wireguard-go)
fi
# Smoke checks for the extra archive, as "expected output|arguments" per
# executable. Every executable in it must have one, so an extra tool cannot
# ship without being started.
# The pinned version is expected, so a version that upstream sets at link time
# cannot silently fall back to a development string.
pinned_version() { awk -F '|' -v n="$1" '$1 == n { print $2 }' "$repo_root/sources.lock"; }
declare -A extra_smoke=(
    [rclone]="rclone v$(pinned_version rclone)|version"
    [croc]="croc version $(pinned_version croc)|--version"
    [crictl]="crictl version v$(pinned_version cri-tools)|--version"
    [ctr]="ctr github.com/containerd/containerd/v2 v$(pinned_version containerd)|--version"
)

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
# Every extra tool is a Go tool, so an extra archive holds all of them.
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


for link in nc netcat dropbear dbclient dropbearkey dropbearconvert scp tunpipe \
    fsck.ext2 fsck.ext3 fsck.ext4 mkfs.ext4 \
    unzstd zstdcat unxz xzcat bunzip2 bzcat unpigz \
    modinfo lsmod insmod rmmod modprobe depmod ping6 traceroute6 \
    iptables-legacy iptables-legacy-save iptables-legacy-restore \
    ip6tables-legacy ip6tables-legacy-save ip6tables-legacy-restore; do
    [[ -L $output_dir/$link ]] || {
        echo "missing applet link: $output_dir/$link" >&2
        exit 1
    }
done

runner=()
if [[ ${SKIP_QEMU:-0} != 1 ]]; then
    if [[ $arch == x86_64 && $(uname -m) == x86_64 ]]; then
        runner=()
    elif command -v "$qemu" >/dev/null 2>&1; then
        runner=("$qemu")
    elif command -v "${qemu}-static" >/dev/null 2>&1; then
        runner=("${qemu}-static")
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
    if [[ ${#runner[@]} -eq 0 ]]; then
        check_output nftables "$output_dir/nft" --version
    fi
    check_output OpenSSL "$output_dir/openssl" version
    check_output tcpdump "$output_dir/tcpdump" --version
    check_output curl "$output_dir/curl" --version
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
    if [[ ${#runner[@]} -eq 0 ]]; then
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
    # tcpreplay probes every interface's link state with an ethtool ioctl
    # before it reads -V, which qemu-user does not emulate. Under emulation
    # that error proves it started; natively, -V runs.
    if [[ ${#runner[@]} -eq 0 ]]; then
        check_output "tcpreplay version: $(pinned_version tcpreplay)" "$output_dir/tcpreplay" -V
    else
        tcpreplay_output=$("${runner[@]}" "$output_dir/tcpreplay" -V 2>&1) || true
        [[ $tcpreplay_output == *"tcpreplay version: $(pinned_version tcpreplay)"* ||
            $tcpreplay_output == *"SIOCETHTOOL(ETHTOOL_GLINK) ioctl failed"* ]] || {
            echo "unexpected output from tcpreplay -V: $tcpreplay_output" >&2
            exit 1
        }
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
    check_output "10.0.0.1:40000 -> 10.0.0.2:80" "$output_dir/ngrep" -q -I "$scratch/smoke.pcap" statics-smoke
    "${runner[@]}" "$output_dir/tcpprep" --auto=bridge --pcap="$scratch/smoke.pcap" \
        --cachefile="$scratch/smoke.cache" || failed "tcpprep"
    "${runner[@]}" "$output_dir/tcprewrite" --infile="$scratch/smoke.pcap" \
        --outfile="$scratch/rewritten.pcap" --cachefile="$scratch/smoke.cache" \
        --dstipmap=10.0.0.2/32:10.0.0.9/32 --fixcsum || failed "tcprewrite"
    check_output "10.0.0.1:40000 -> 10.0.0.9:80" "$output_dir/ngrep" -q -I "$scratch/rewritten.pcap" statics-smoke
    check_output "cksum 0x01d2 (correct)" "$output_dir/tcpdump" -vvnr "$scratch/rewritten.pcap" tcp
    if [[ $go_env != none ]]; then
        check_output "wireguard-go v" "$output_dir/wireguard-go" --version
    fi
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
