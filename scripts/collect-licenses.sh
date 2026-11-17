#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [[ $# -ne 4 ]]; then
    echo "usage: $0 SOURCE_ROOT OUTPUT_DIR ARCH main|extra" >&2
    exit 2
fi

source_root=$1
output_dir=$2
license_root="$output_dir/licenses"
# The components in this archive; licenses of any other are skipped.
components=$("$repo_root/scripts/components.sh" "$3" "$4")
active=" $(cut -d '|' -f 1 <<<"$components" | tr '\n' ' ')"

copy_license() {
    local source_name=$1
    local relative_path=$2
    [[ $active == *" $source_name "* ]] || return 0
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
copy_license libnftnl COPYING
copy_license nftables COPYING
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
copy_license util-linux Documentation/licenses/COPYING.BSD-3-Clause
copy_license util-linux Documentation/licenses/COPYING.BSD-2-Clause
copy_license util-linux Documentation/licenses/COPYING.MIT
copy_license util-linux libuuid/COPYING
copy_license util-linux UTIL-LINUX-NOTICES
copy_license e2fsprogs NOTICE
copy_license smartmontools COPYING
copy_license libnvme COPYING
copy_license nvme-cli LICENSE
copy_license ppp COPYING
copy_license ppp LICENSE.BSD
copy_license ppp PPPD-NOTICES
copy_license picocom LICENSE.txt
copy_license picocom linenoise-1.0/LICENSE
copy_license lrzsz COPYING
copy_license gdb COPYING
copy_license gdb COPYING3
copy_license gdb COPYING.LIB
copy_license gdb libiberty/COPYING.LIB
copy_license gdb LIBIBERTY-BSD-NOTICES
copy_license openssh LICENCE
copy_license libnfnetlink COPYING
copy_license libnetfilter_conntrack COPYING
copy_license conntrack-tools COPYING
copy_license ipmitool COPYING
copy_license mtd-utils COPYING
copy_license mtd-utils MTD-UTILS-BSD-NOTICES
copy_license libnl COPYING
copy_license iw COPYING
copy_license wireguard-go LICENSE
copy_license rclone COPYING
copy_license croc LICENSE
copy_license cri-tools LICENSE
copy_license containerd LICENSE
copy_license containerd NOTICE

# Go's runtime and standard library come from the toolchain that linked them.
if [[ $active == *" go "* ]]; then
    for file in LICENSE PATENTS; do
        install -D -m 0644 "$(go env GOROOT)/$file" "$license_root/go/$file"
    done
fi
# Each Go tool's module list and module notices, staged by go_build.
while IFS='|' read -r source_name _ _ _ packages; do
    [[ -z $source_name || $packages == - || $packages == runtime ]] && continue
    cp -R "$source_root/go-licenses/$source_name/." "$license_root/$source_name/"
done <<<"$components"

{
    head -n 1 "$repo_root/components.tsv"
    printf '%s\n' "$components"
} > "$output_dir/COMPONENTS.tsv"

{
    echo "# Third-party notices"
    echo
    echo "This bundle contains software from the projects below. The SPDX"
    echo "expressions are an index; the complete upstream notices are under"
    echo "\`licenses/<source>/\`. Upstream projects retain their copyrights."
    echo
    echo "| Source | Version | SPDX expression | Role |"
    echo "| --- | --- | --- | --- |"
    while IFS='|' read -r source_name license_expression role _; do
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
    done <<<"$components"
    echo
    echo "The exact source archives and checksums are recorded in \`sources.lock\`."
    if [[ $active == *" go "* ]]; then
        echo
        echo "Each Go tool also links the Go modules listed, with their versions and"
        echo "go.sum hashes, in \`licenses/<source>/go-modules.tsv\`. Their license"
        echo "and notice files are under \`licenses/<source>/modules/<module>@<version>/\`."
    fi
} > "$output_dir/THIRD_PARTY_NOTICES.md"

cp "$repo_root/LICENSE" "$output_dir/BUILD_RECIPES_LICENSE"
