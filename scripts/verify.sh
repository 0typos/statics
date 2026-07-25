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
IFS='|' read -r _ _ _ qemu _ <<<"$record"

required_binaries=(
    busybox socat dropbearmulti
    ip ss bridge tc wg
    openssl tcpdump curl iperf3 ethtool strace jq drill mtr mtr-packet
    candump cansend cangen canplayer cansniffer
    isotpdump isotprecv isotpsend slcand canbusload
    i2cdetect i2cdump i2cget i2cset i2ctransfer
    spi-config spi-pipe
    nmap ncat rsync lsof
    nsenter unshare lsns setpriv findmnt
)

for metadata in BUILDINFO BUILD_RECIPES_LICENSE COMPONENTS.tsv SBOM.spdx.json \
    SHA256SUMS THIRD_PARTY_NOTICES.md sources.lock; do
    [[ -s $output_dir/$metadata ]] || {
        echo "missing build metadata: $output_dir/$metadata" >&2
        exit 1
    }
done

for binary in "${required_binaries[@]}"; do
    [[ -x $output_dir/$binary ]] || {
        echo "missing executable: $output_dir/$binary" >&2
        exit 1
    }
done

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

while IFS='|' read -r source_name _; do
    [[ $source_name == \#* || -z $source_name ]] && continue
    [[ -d $output_dir/licenses/$source_name ]] || {
        echo "missing license directory: $output_dir/licenses/$source_name" >&2
        exit 1
    }
    find "$output_dir/licenses/$source_name" -type f -size +0c -print -quit |
        grep -q . || {
        echo "empty license directory: $output_dir/licenses/$source_name" >&2
        exit 1
    }
done < "$repo_root/components.tsv"

python3 - "$output_dir/SBOM.spdx.json" "$arch" <<'PY'
import json
import hashlib
import re
import sys
from pathlib import Path

path, arch = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    document = json.load(handle)
if document.get("spdxVersion") != "SPDX-2.3":
    raise SystemExit("unexpected SPDX version")
if document.get("name") != f"statics-{arch}":
    raise SystemExit("unexpected SPDX document name")
if not document.get("packages") or not document.get("files"):
    raise SystemExit("SPDX document has no packages or files")
license_list = document.get("creationInfo", {}).get("licenseListVersion", "")
if not re.fullmatch(r"\d+\.\d+", license_list):
    raise SystemExit("invalid SPDX license-list version")

bundle = next(
    package
    for package in document["packages"]
    if package.get("name") == f"statics-{arch}"
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

while IFS= read -r binary; do
    file "$output_dir/$binary"
    file "$output_dir/$binary" | grep -Eq 'statically linked|static-pie linked' || {
        echo "$binary is not statically linked" >&2
        exit 1
    }
    if readelf --program-headers "$output_dir/$binary" | grep -q 'Requesting program interpreter'; then
        echo "$binary has a dynamic program interpreter" >&2
        exit 1
    fi
done < <(
    cd "$output_dir"
    find . -maxdepth 1 -type f -perm /111 -printf '%P\n' | LC_ALL=C sort
)

for link in nc netcat dropbear dbclient dropbearkey dropbearconvert scp; do
    [[ -L $output_dir/$link ]] || {
        echo "missing applet link: $output_dir/$link" >&2
        exit 1
    }
done

(
    cd "$output_dir"
    sha256sum --check SHA256SUMS
)

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
    "${runner[@]}" "$output_dir/socat" -V >/dev/null
    check_output Dropbear "$output_dir/dropbearmulti" dropbear -V
    check_output iproute2 "$output_dir/ip" -Version
    check_output iproute2 "$output_dir/ss" -V
    check_output "bridge utility" "$output_dir/bridge" -V
    check_output iproute2 "$output_dir/tc" -V
    check_output wireguard-tools "$output_dir/wg" --version
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
    check_output util-linux "$output_dir/nsenter" --version
    check_output util-linux "$output_dir/unshare" --version
    check_output util-linux "$output_dir/lsns" --version
    check_output util-linux "$output_dir/setpriv" --version
    check_output util-linux "$output_dir/findmnt" --version
fi

echo "verified $arch"
