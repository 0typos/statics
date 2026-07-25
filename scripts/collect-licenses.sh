#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [[ $# -ne 2 ]]; then
    echo "usage: $0 SOURCE_ROOT OUTPUT_DIR" >&2
    exit 2
fi

source_root=$1
output_dir=$2
license_root="$output_dir/licenses"

copy_license() {
    local source_name=$1
    local relative_path=$2
    local source_path="$source_root/$source_name/$relative_path"
    local destination="$license_root/$source_name/$relative_path"

    [[ -f $source_path ]] || {
        echo "missing license file: $source_path" >&2
        exit 1
    }
    mkdir -p "$(dirname "$destination")"
    install -m 0644 "$source_path" "$destination"
}

rm -rf "$license_root"
mkdir -p "$license_root"

copy_license busybox LICENSE
copy_license socat COPYING
copy_license socat COPYING.OpenSSL
copy_license dropbear LICENSE
copy_license dropbear libtomcrypt/LICENSE
copy_license dropbear libtommath/LICENSE
copy_license iproute2 COPYING
copy_license wireguard-tools COPYING
copy_license openssl LICENSE.txt
copy_license libpcap LICENSE
copy_license libmnl COPYING
copy_license libcap-ng COPYING
copy_license libcap-ng COPYING.LIB
copy_license tcpdump LICENSE
copy_license curl COPYING
copy_license iperf3 LICENSE
copy_license ethtool COPYING
copy_license ethtool LICENSE
copy_license strace COPYING
copy_license strace bundled/linux/COPYING
copy_license jq COPYING
copy_license jq vendor/oniguruma/COPYING
copy_license ldns LICENSE
copy_license mtr COPYING
copy_license can-utils LICENSES/BSD-3-Clause
copy_license can-utils LICENSES/GPL-2.0-only.txt
copy_license can-utils LICENSES/Linux-syscall-note.txt
copy_license i2c-tools COPYING
copy_license i2c-tools COPYING.LGPL
copy_license spi-tools LICENSE
copy_license nmap LICENSE
copy_license nmap ncat/LICENSE
copy_license nmap docs/3rd-party-licenses.txt
copy_license rsync COPYING
copy_license rsync popt/COPYING
copy_license rsync zlib/zlib.h
copy_license lsof COPYING
copy_license util-linux COPYING
copy_license util-linux README.licensing
copy_license util-linux Documentation/licenses/COPYING.GPL-2.0-only
copy_license util-linux Documentation/licenses/COPYING.GPL-2.0-or-later
copy_license util-linux Documentation/licenses/COPYING.LGPL-2.1-or-later

cp "$repo_root/components.tsv" "$output_dir/COMPONENTS.tsv"

{
    echo "# Third-party notices"
    echo
    echo "This bundle contains software from the projects below. The SPDX"
    echo "expressions are an index; the complete upstream notices are under"
    echo "\`licenses/<source>/\`. Upstream projects retain their copyrights."
    echo
    echo "| Source | Version | SPDX expression | Role |"
    echo "| --- | --- | --- | --- |"
    while IFS='|' read -r source_name license_expression role; do
        [[ $source_name == \#* || -z $source_name ]] && continue
        record=$(awk -F '|' -v wanted="$source_name" '
            $0 !~ /^#/ && $1 == wanted { print; found++ }
            END { if (found != 1) exit 1 }
        ' "$repo_root/sources.lock") || {
            echo "missing source lock record for $source_name" >&2
            exit 1
        }
        IFS='|' read -r _ version _ url <<<"$record"
        printf "| [%s](%s) | \`%s\` | \`%s\` | %s |\n" \
            "$source_name" "$url" "$version" "$license_expression" "$role"
    done < "$repo_root/components.tsv"
    echo
    echo "The exact source archives and checksums are recorded in \`sources.lock\`."
} > "$output_dir/THIRD_PARTY_NOTICES.md"

cp "$repo_root/LICENSE" "$output_dir/BUILD_RECIPES_LICENSE"
