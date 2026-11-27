#!/usr/bin/env python3
"""Discover upstream releases and update sources.lock with reviewed checksums."""

from __future__ import annotations

import argparse
import dataclasses
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Callable


ROOT = Path(__file__).resolve().parent.parent
LOCK_PATH = ROOT / "sources.lock"
USER_AGENT = "statics-source-updater/1.0"


@dataclasses.dataclass(frozen=True)
class Source:
    name: str
    version: str
    sha256: str
    url: str


def request(url: str) -> urllib.request.addinfourl:
    headers = {"User-Agent": USER_AGENT}
    token = os.environ.get("GITHUB_TOKEN")
    if token and url.startswith("https://api.github.com/"):
        headers["Authorization"] = f"Bearer {token}"
    prepared = urllib.request.Request(url, headers=headers)
    for attempt in range(3):
        try:
            return urllib.request.urlopen(  # noqa: S310 - fixed upstream URLs.
                prepared,
                timeout=60,
            )
        except urllib.error.HTTPError as error:
            if error.code < 500 and error.code != 429:
                raise
            if attempt == 2:
                raise
        except urllib.error.URLError:
            if attempt == 2:
                raise
        time.sleep(2**attempt)
    raise AssertionError("retry loop exhausted")


def text(url: str) -> str:
    with request(url) as response:
        return response.read().decode("utf-8")


def numeric_version(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in version.split("."))


def latest_from_index(
    index_url: str,
    pattern: str,
    url_template: str,
) -> tuple[str, str]:
    versions = set(re.findall(pattern, text(index_url)))
    if not versions:
        raise RuntimeError(f"no releases found at {index_url}")
    version = max(versions, key=numeric_version)
    return version, url_template.format(version=version)


def latest_from_github_tags(
    repository: str,
    pattern: str,
    url_template: str,
) -> tuple[str, str]:
    tags = json.loads(
        text(f"https://api.github.com/repos/{repository}/tags?per_page=100")
    )
    versions = [
        match.group(1)
        for tag in tags
        if (match := re.fullmatch(pattern, tag["name"]))
    ]
    if not versions:
        raise RuntimeError(f"no matching tags found for {repository}")
    version = max(versions, key=numeric_version)
    return version, url_template.format(version=version)


def latest_from_github_release(
    repository: str,
    pattern: str,
    url_template: str,
) -> tuple[str, str]:
    release = json.loads(
        text(f"https://api.github.com/repos/{repository}/releases/latest")
    )
    match = re.fullmatch(pattern, release["tag_name"])
    if match is None:
        raise RuntimeError(
            f"latest release tag does not match for {repository}: "
            f"{release['tag_name']}"
        )
    version = match.group(1)
    url = url_template.format(version=version)
    asset_urls = {
        asset["browser_download_url"] for asset in release.get("assets", [])
    }
    if url not in asset_urls:
        raise RuntimeError(f"release asset not found for {repository}: {url}")
    return version, url


def latest_busybox() -> tuple[str, str]:
    return latest_from_index(
        "https://busybox.net/downloads/",
        r'busybox-(\d+\.\d+\.\d+)\.tar\.bz2"',
        "https://busybox.net/downloads/busybox-{version}.tar.bz2",
    )


def latest_socat() -> tuple[str, str]:
    # Upstream's HTTPS certificate does not cover this hostname. The pinned
    # SHA-256 protects builds after a human reviews the update PR.
    return latest_from_index(
        "http://www.dest-unreach.org/socat/",
        r'socat-(\d+\.\d+\.\d+\.\d+)\.tar\.gz',
        "http://www.dest-unreach.org/socat/download/socat-{version}.tar.gz",
    )


def latest_dropbear() -> tuple[str, str]:
    return latest_from_index(
        "https://matt.ucc.asn.au/dropbear/releases/",
        r'dropbear-(\d{4}\.\d+)\.tar\.bz2',
        "https://matt.ucc.asn.au/dropbear/releases/dropbear-{version}.tar.bz2",
    )


def latest_iproute2() -> tuple[str, str]:
    return latest_from_index(
        "https://mirrors.edge.kernel.org/pub/linux/utils/net/iproute2/",
        r'iproute2-(\d+\.\d+\.\d+)\.tar\.xz',
        (
            "https://cdn.kernel.org/pub/linux/utils/net/iproute2/"
            "iproute2-{version}.tar.xz"
        ),
    )


def latest_wireguard_tools() -> tuple[str, str]:
    return latest_from_github_tags(
        "WireGuard/wireguard-tools",
        r"v(\d+\.\d+\.\d+)",
        (
            "https://github.com/WireGuard/wireguard-tools/archive/refs/tags/"
            "v{version}.tar.gz"
        ),
    )


def latest_openssl() -> tuple[str, str]:
    # Track the supported 3.5 LTS branch instead of automatically changing
    # the dependency ABI to a new OpenSSL major/minor release.
    return latest_from_github_tags(
        "openssl/openssl",
        r"openssl-(3\.5\.\d+)",
        (
            "https://github.com/openssl/openssl/releases/download/"
            "openssl-{version}/openssl-{version}.tar.gz"
        ),
    )


def latest_libpcap() -> tuple[str, str]:
    return latest_from_github_tags(
        "the-tcpdump-group/libpcap",
        r"libpcap-(\d+\.\d+\.\d+)",
        "https://www.tcpdump.org/release/libpcap-{version}.tar.xz",
    )


def latest_tcpdump() -> tuple[str, str]:
    return latest_from_github_tags(
        "the-tcpdump-group/tcpdump",
        r"tcpdump-(\d+\.\d+\.\d+)",
        "https://www.tcpdump.org/release/tcpdump-{version}.tar.xz",
    )


def latest_libmnl() -> tuple[str, str]:
    return latest_from_index(
        "https://www.netfilter.org/projects/libmnl/downloads.html",
        r"libmnl-(\d+\.\d+\.\d+)\.tar\.bz2",
        (
            "https://www.netfilter.org/projects/libmnl/files/"
            "libmnl-{version}.tar.bz2"
        ),
    )


def latest_libcap_ng() -> tuple[str, str]:
    return latest_from_github_tags(
        "stevegrubb/libcap-ng",
        r"v(\d+\.\d+(?:\.\d+)?)",
        (
            "https://github.com/stevegrubb/libcap-ng/archive/refs/tags/"
            "v{version}.tar.gz"
        ),
    )


def latest_curl() -> tuple[str, str]:
    return latest_from_index(
        "https://curl.se/download.html",
        r"curl-(\d+\.\d+\.\d+)\.tar\.xz",
        "https://curl.se/download/curl-{version}.tar.xz",
    )


def latest_iperf3() -> tuple[str, str]:
    return latest_from_index(
        "https://downloads.es.net/pub/iperf/",
        r"iperf-(\d+\.\d+)\.tar\.gz",
        "https://downloads.es.net/pub/iperf/iperf-{version}.tar.gz",
    )


def latest_ethtool() -> tuple[str, str]:
    return latest_from_index(
        "https://mirrors.edge.kernel.org/pub/software/network/ethtool/",
        r"ethtool-(\d+\.\d+)\.tar\.xz",
        (
            "https://cdn.kernel.org/pub/software/network/ethtool/"
            "ethtool-{version}.tar.xz"
        ),
    )


def latest_strace() -> tuple[str, str]:
    return latest_from_index(
        "https://strace.io/files/",
        r'href="(\d+\.\d+)/"',
        "https://strace.io/files/{version}/strace-{version}.tar.xz",
    )


def latest_jq() -> tuple[str, str]:
    return latest_from_github_tags(
        "jqlang/jq",
        r"jq-(\d+\.\d+\.\d+)",
        (
            "https://github.com/jqlang/jq/releases/download/"
            "jq-{version}/jq-{version}.tar.gz"
        ),
    )


def latest_ldns() -> tuple[str, str]:
    return latest_from_index(
        "https://nlnetlabs.nl/downloads/ldns/",
        r"ldns-(\d+\.\d+\.\d+)\.tar\.gz",
        "https://nlnetlabs.nl/downloads/ldns/ldns-{version}.tar.gz",
    )


def latest_mtr() -> tuple[str, str]:
    return latest_from_github_tags(
        "traviscross/mtr",
        r"v(\d+\.\d+)",
        (
            "https://github.com/traviscross/mtr/archive/refs/tags/"
            "v{version}.tar.gz"
        ),
    )


def latest_can_utils() -> tuple[str, str]:
    return latest_from_github_tags(
        "linux-can/can-utils",
        r"v(\d{4}\.\d+)",
        (
            "https://github.com/linux-can/can-utils/archive/refs/tags/"
            "v{version}.tar.gz"
        ),
    )


def latest_i2c_tools() -> tuple[str, str]:
    return latest_from_index(
        "https://mirrors.edge.kernel.org/pub/software/utils/i2c-tools/",
        r"i2c-tools-(\d+\.\d+)\.tar\.xz",
        (
            "https://cdn.kernel.org/pub/software/utils/i2c-tools/"
            "i2c-tools-{version}.tar.xz"
        ),
    )


def latest_spi_tools() -> tuple[str, str]:
    commits = json.loads(
        text("https://api.github.com/repos/cpb-/spi-tools/commits?per_page=1")
    )
    if not commits:
        raise RuntimeError("no spi-tools commits found")
    commit = commits[0]["sha"]
    return (
        commit[:12],
        f"https://github.com/cpb-/spi-tools/archive/{commit}.tar.gz",
    )


def latest_nmap() -> tuple[str, str]:
    return latest_from_index(
        "https://nmap.org/dist/",
        r"nmap-(\d+\.\d+)\.tar\.bz2",
        "https://nmap.org/dist/nmap-{version}.tar.bz2",
    )


def latest_rsync() -> tuple[str, str]:
    return latest_from_index(
        "https://download.samba.org/pub/rsync/src/",
        r"rsync-(\d+\.\d+\.\d+)\.tar\.gz",
        (
            "https://download.samba.org/pub/rsync/src/"
            "rsync-{version}.tar.gz"
        ),
    )


def latest_lsof() -> tuple[str, str]:
    return latest_from_github_release(
        "lsof-org/lsof",
        r"(\d+\.\d+\.\d+)",
        (
            "https://github.com/lsof-org/lsof/releases/download/"
            "{version}/lsof-{version}.tar.gz"
        ),
    )


def latest_util_linux() -> tuple[str, str]:
    root = "https://www.kernel.org/pub/linux/utils/util-linux/"
    branches = set(re.findall(r'href="v(\d+\.\d+)/"', text(root)))
    if not branches:
        raise RuntimeError(f"no util-linux release branches found at {root}")
    branch = max(branches, key=numeric_version)
    return latest_from_index(
        f"{root}v{branch}/",
        rf"util-linux-({re.escape(branch)}(?:\.\d+)?)\.tar\.xz",
        f"{root}v{branch}/util-linux-{{version}}.tar.xz",
    )


def latest_ppp() -> tuple[str, str]:
    return latest_from_index(
        "https://download.samba.org/pub/ppp/",
        r'ppp-(\d+\.\d+\.\d+)\.tar\.gz"',
        "https://download.samba.org/pub/ppp/ppp-{version}.tar.gz",
    )


def latest_picocom() -> tuple[str, str]:
    return latest_from_github_tags(
        "npat-efault/picocom",
        r"(\d+\.\d+)",
        "https://github.com/npat-efault/picocom/archive/refs/tags/{version}.tar.gz",
    )


def latest_lrzsz() -> tuple[str, str]:
    return latest_from_index(
        "https://ohse.de/uwe/software/lrzsz.html",
        r"lrzsz-(\d+\.\d+\.\d+)\.tar\.gz",
        "https://ohse.de/uwe/releases/lrzsz-{version}.tar.gz",
    )


def latest_gdb() -> tuple[str, str]:
    return latest_from_index(
        "https://ftp.gnu.org/gnu/gdb/",
        r'gdb-(\d+\.\d+(?:\.\d+)?)\.tar\.xz"',
        "https://ftp.gnu.org/gnu/gdb/gdb-{version}.tar.xz",
    )


def latest_openssh() -> tuple[str, str]:
    # Portable releases are versioned like 10.6p2, which numeric_version
    # cannot order; compare every number in the version instead.
    index = "https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/"
    versions = set(
        re.findall(r'openssh-(\d+\.\d+p\d+)\.tar\.gz"', text(index))
    )
    if not versions:
        raise RuntimeError(f"no releases found at {index}")
    version = max(
        versions, key=lambda v: tuple(int(n) for n in re.findall(r"\d+", v))
    )
    return version, f"{index}openssh-{version}.tar.gz"


def latest_netfilter(project: str, extension: str) -> tuple[str, str]:
    return latest_from_index(
        f"https://www.netfilter.org/projects/{project}/downloads.html",
        rf"{re.escape(project)}-(\d+\.\d+\.\d+)\.tar\.{extension}",
        (
            f"https://www.netfilter.org/pub/{project}/"
            f"{project}-{{version}}.tar.{extension}"
        ),
    )


def latest_ipmitool() -> tuple[str, str]:
    # Tags look like IPMITOOL_1_8_19; int() would accept "1_8_19" whole.
    tags = json.loads(
        text("https://api.github.com/repos/ipmitool/ipmitool/tags?per_page=100")
    )
    versions = [
        ".".join(match.groups())
        for tag in tags
        if (match := re.fullmatch(r"IPMITOOL_(\d+)_(\d+)_(\d+)", tag["name"]))
    ]
    if not versions:
        raise RuntimeError("no matching tags found for ipmitool/ipmitool")
    version = max(versions, key=numeric_version)
    tag = "IPMITOOL_" + version.replace(".", "_")
    return (
        version,
        f"https://github.com/ipmitool/ipmitool/archive/refs/tags/{tag}.tar.gz",
    )


def latest_mtd_utils() -> tuple[str, str]:
    return latest_from_index(
        "https://infraroot.at/pub/mtd/",
        r"mtd-utils-(\d+\.\d+\.\d+)\.tar\.bz2",
        "https://infraroot.at/pub/mtd/mtd-utils-{version}.tar.bz2",
    )


def latest_libnl() -> tuple[str, str]:
    release = json.loads(
        text("https://api.github.com/repos/thom311/libnl/releases/latest")
    )
    match = re.fullmatch(r"libnl(\d+)_(\d+)_(\d+)", release["tag_name"])
    if match is None:
        raise RuntimeError(f"unexpected libnl tag: {release['tag_name']}")
    version = ".".join(match.groups())
    url = (
        "https://github.com/thom311/libnl/releases/download/"
        f"{release['tag_name']}/libnl-{version}.tar.gz"
    )
    if url not in {
        asset["browser_download_url"] for asset in release.get("assets", [])
    }:
        raise RuntimeError(f"release asset not found for libnl: {url}")
    return version, url


def latest_iw() -> tuple[str, str]:
    return latest_from_index(
        "https://mirrors.edge.kernel.org/pub/software/network/iw/",
        r"iw-(\d+\.\d+)\.tar\.xz",
        "https://cdn.kernel.org/pub/software/network/iw/iw-{version}.tar.xz",
    )


def latest_zlib() -> tuple[str, str]:
    return latest_from_github_release(
        "madler/zlib",
        r"v(\d+\.\d+(?:\.\d+)*)",
        "https://github.com/madler/zlib/releases/download/v{version}/zlib-{version}.tar.xz",
    )


def latest_bzip2() -> tuple[str, str]:
    return latest_from_index(
        "https://sourceware.org/pub/bzip2/",
        r'bzip2-(\d+\.\d+\.\d+)\.tar\.gz"',
        "https://sourceware.org/pub/bzip2/bzip2-{version}.tar.gz",
    )


def latest_xz() -> tuple[str, str]:
    return latest_from_github_release(
        "tukaani-project/xz",
        r"v(\d+\.\d+\.\d+)",
        (
            "https://github.com/tukaani-project/xz/releases/download/"
            "v{version}/xz-{version}.tar.xz"
        ),
    )


def latest_zstd() -> tuple[str, str]:
    return latest_from_github_release(
        "meta/zstd",
        r"v(\d+\.\d+\.\d+)",
        "https://github.com/meta/zstd/releases/download/v{version}/zstd-{version}.tar.gz",
    )


def latest_pigz() -> tuple[str, str]:
    # zlib.net/pigz/ links only the current release, which fossils/ keeps
    # with all the others (and a misnamed 2008 pigz-2.11 to avoid).
    return latest_from_index(
        "https://zlib.net/pigz/",
        r'pigz-(\d+\.\d+(?:\.\d+)?)\.tar\.gz"',
        "https://zlib.net/pigz/fossils/pigz-{version}.tar.gz",
    )


def latest_pv() -> tuple[str, str]:
    # ivarch.com announces releases but keeps only the current archive;
    # Codeberg's release assets are the same files and stay.
    return latest_from_index(
        "https://www.ivarch.com/programs/pv.shtml",
        r"pv-(\d+\.\d+\.\d+)\.tar\.gz",
        (
            "https://codeberg.org/ivarch/pv/releases/download/"
            "v{version}/pv-{version}.tar.gz"
        ),
    )


def latest_mbuffer() -> tuple[str, str]:
    return latest_from_index(
        "https://www.maier-komor.de/mbuffer.html",
        r"mbuffer-(\d{8})\.tgz",
        "https://www.maier-komor.de/software/mbuffer/mbuffer-{version}.tgz",
    )


def latest_libarchive() -> tuple[str, str]:
    return latest_from_github_release(
        "libarchive/libarchive",
        r"v(\d+\.\d+\.\d+)",
        (
            "https://github.com/libarchive/libarchive/releases/download/"
            "v{version}/libarchive-{version}.tar.xz"
        ),
    )


def latest_kmod() -> tuple[str, str]:
    return latest_from_index(
        "https://mirrors.edge.kernel.org/pub/linux/utils/kernel/kmod/",
        r"kmod-(\d+(?:\.\d+)*)\.tar\.xz",
        "https://cdn.kernel.org/pub/linux/utils/kernel/kmod/kmod-{version}.tar.xz",
    )


def latest_kexec_tools() -> tuple[str, str]:
    return latest_from_index(
        "https://mirrors.edge.kernel.org/pub/linux/utils/kernel/kexec/",
        r"kexec-tools-(\d+\.\d+\.\d+)\.tar\.xz",
        (
            "https://cdn.kernel.org/pub/linux/utils/kernel/kexec/"
            "kexec-tools-{version}.tar.xz"
        ),
    )


def latest_elfutils() -> tuple[str, str]:
    return latest_from_index(
        "https://sourceware.org/elfutils/ftp/",
        r'href="(\d+\.\d+)/"',
        "https://sourceware.org/elfutils/ftp/{version}/elfutils-{version}.tar.bz2",
    )


def latest_bpftool() -> tuple[str, str]:
    # The release's sources archive bundles the libbpf it was tested with.
    return latest_from_github_release(
        "libbpf/bpftool",
        r"v(\d+\.\d+\.\d+)",
        (
            "https://github.com/libbpf/bpftool/releases/download/"
            "v{version}/bpftool-libbpf-v{version}-sources.tar.gz"
        ),
    )


def latest_iputils() -> tuple[str, str]:
    return latest_from_github_release(
        "iputils/iputils",
        r"(\d{8})",
        (
            "https://github.com/iputils/iputils/releases/download/"
            "{version}/iputils-{version}.tar.xz"
        ),
    )


def latest_traceroute() -> tuple[str, str]:
    return latest_from_index(
        "https://sourceforge.net/projects/traceroute/rss?path=/traceroute",
        r"traceroute-(\d+\.\d+\.\d+)\.tar\.gz",
        (
            "https://downloads.sourceforge.net/project/traceroute/traceroute/"
            "traceroute-{version}/traceroute-{version}.tar.gz"
        ),
    )


def latest_ndisc6() -> tuple[str, str]:
    return latest_from_index(
        "https://www.remlab.net/files/ndisc6/",
        r"ndisc6-(\d+\.\d+\.\d+)\.tar\.bz2",
        "https://www.remlab.net/files/ndisc6/ndisc6-{version}.tar.bz2",
    )


def latest_lldpd() -> tuple[str, str]:
    # The archive upstream signs is on its own host, not the GitHub release.
    return latest_from_github_tags(
        "lldpd/lldpd",
        r"(\d+\.\d+\.\d+)",
        "https://media.luffy.cx/files/lldpd/lldpd-{version}.tar.gz",
    )


def latest_netfilter_pub(
    project: str, pattern: str, extension: str
) -> tuple[str, str]:
    return latest_from_index(
        f"https://www.netfilter.org/pub/{project}/",
        rf"{re.escape(project)}-({pattern})\.tar\.{extension}",
        (
            f"https://www.netfilter.org/pub/{project}/"
            f"{project}-{{version}}.tar.{extension}"
        ),
    )


def latest_ngrep() -> tuple[str, str]:
    return latest_from_github_tags(
        "jpr5/ngrep",
        r"v(\d+\.\d+\.\d+)",
        "https://github.com/jpr5/ngrep/archive/refs/tags/v{version}.tar.gz",
    )


def latest_hping3(part: str) -> tuple[str, str]:
    # Upstream hping3 is gone; Debian's newest upload is the maintained
    # line. Both archives are taken from snapshot.debian.org at the time
    # that upload's patch set was first seen, so the URLs stay valid.
    package = "https://snapshot.debian.org/mr/package/hping3"
    version = json.loads(text(f"{package}/"))["result"][0]["version"]
    files = json.loads(text(f"{package}/{version}/srcfiles?fileinfo=1"))
    seen = {
        info["name"]: info["first_seen"]
        for infos in files["fileinfo"].values()
        for info in infos
        if info["archive_name"] == "debian"
    }
    patches = f"hping3_{version}.debian.tar.xz"
    upstream = version.rsplit("-", 1)[0]
    name = patches if part == "debian" else f"hping3_{upstream}.orig.tar.gz"
    if patches not in seen or name not in seen:
        raise RuntimeError(f"hping3 {version} has no {name} in snapshot.debian.org")
    url = (
        f"https://snapshot.debian.org/archive/debian/{seen[patches]}"
        f"/pool/main/h/hping3/{name}"
    )
    return (version if part == "debian" else upstream), url


def latest_ncurses() -> tuple[str, str]:
    return latest_from_index(
        "https://ftp.gnu.org/gnu/ncurses/",
        r"ncurses-(\d+\.\d+)\.tar\.gz",
        "https://ftp.gnu.org/gnu/ncurses/ncurses-{version}.tar.gz",
    )


def latest_iftop() -> tuple[str, str]:
    # 1.0pre4 sorts before 1.0: numbers first, then final over prerelease.
    index = text("https://pdw.ex-parrot.com/iftop/download/")
    versions = set(re.findall(r"iftop-(\d+\.\d+(?:pre\d+)?)\.tar\.gz", index))
    if not versions:
        raise RuntimeError("no iftop releases found")
    version = max(
        versions,
        key=lambda v: (
            tuple(int(part) for part in re.split(r"\D+", v.split("pre")[0])),
            "pre" not in v,
            int(v.split("pre")[1]) if "pre" in v else 0,
        ),
    )
    return version, f"https://pdw.ex-parrot.com/iftop/download/iftop-{version}.tar.gz"


def latest_nethogs() -> tuple[str, str]:
    return latest_from_github_tags(
        "raboof/nethogs",
        r"v(\d+\.\d+\.\d+)",
        "https://github.com/raboof/nethogs/archive/refs/tags/v{version}.tar.gz",
    )


def latest_tcpreplay() -> tuple[str, str]:
    return latest_from_github_release(
        "appneta/tcpreplay",
        r"v(\d+\.\d+\.\d+)",
        (
            "https://github.com/appneta/tcpreplay/releases/download/"
            "v{version}/tcpreplay-{version}.tar.xz"
        ),
    )


def latest_dhcpdump() -> tuple[str, str]:
    return latest_from_github_release(
        "dhcpdump-org/dhcpdump",
        r"v(\d+\.\d+)",
        (
            "https://github.com/dhcpdump-org/dhcpdump/releases/download/"
            "v{version}/dhcpdump-{version}.tar.xz"
        ),
    )


def latest_libevent() -> tuple[str, str]:
    # Stable releases only; the 2.2 line is still tagged alpha.
    return latest_from_github_tags(
        "libevent/libevent",
        r"release-(\d+\.\d+\.\d+)-stable",
        (
            "https://github.com/libevent/libevent/releases/download/"
            "release-{version}-stable/libevent-{version}-stable.tar.gz"
        ),
    )


def latest_tmux() -> tuple[str, str]:
    # Releases such as 3.7c carry a letter, so take GitHub's latest.
    return latest_from_github_release(
        "tmux/tmux",
        r"(\d+\.\d+[a-z]?)",
        "https://github.com/tmux/tmux/releases/download/{version}/tmux-{version}.tar.gz",
    )


def latest_stunnel() -> tuple[str, str]:
    # The archive URL stays valid after the next release moves the file
    # out of downloads/.
    version, _ = latest_from_index(
        "https://www.stunnel.org/downloads.html",
        r"stunnel-(\d+\.\d+)\.tar\.gz",
        "",
    )
    major = version.split(".")[0]
    return version, (
        f"https://www.stunnel.org/archive/{major}.x/stunnel-{version}.tar.gz"
    )


def latest_openvpn() -> tuple[str, str]:
    # Tags, not GitHub's latest release: a 2.6 maintenance release can be
    # published after the newest 2.7 one.
    return latest_from_github_tags(
        "OpenVPN/openvpn",
        r"v(\d+\.\d+\.\d+)",
        (
            "https://github.com/OpenVPN/openvpn/releases/download/"
            "v{version}/openvpn-{version}.tar.gz"
        ),
    )


def latest_microsocks() -> tuple[str, str]:
    return latest_from_github_tags(
        "rofl0r/microsocks",
        r"v(\d+\.\d+\.\d+)",
        "https://github.com/rofl0r/microsocks/archive/refs/tags/v{version}.tar.gz",
    )


def latest_tinyproxy() -> tuple[str, str]:
    return latest_from_github_release(
        "tinyproxy/tinyproxy",
        r"(\d+\.\d+\.\d+)",
        (
            "https://github.com/tinyproxy/tinyproxy/releases/download/"
            "{version}/tinyproxy-{version}.tar.xz"
        ),
    )


def latest_dnsmasq() -> tuple[str, str]:
    # Test and release-candidate tarballs (2.94test1, 2.94rc1) never match.
    return latest_from_index(
        "https://thekelleys.org.uk/dnsmasq/",
        r"dnsmasq-(\d+\.\d+)\.tar\.xz",
        "https://thekelleys.org.uk/dnsmasq/dnsmasq-{version}.tar.xz",
    )


def latest_libyaml() -> tuple[str, str]:
    return latest_from_github_release(
        "yaml/libyaml",
        r"(\d+\.\d+\.\d+)",
        "https://github.com/yaml/libyaml/releases/download/{version}/yaml-{version}.tar.gz",
    )


def latest_cminyard(project: str) -> tuple[str, str]:
    return latest_from_github_release(
        f"cminyard/{project}",
        r"v(\d+\.\d+\.\d+)",
        (
            f"https://github.com/cminyard/{project}/releases/download/"
            f"v{{version}}/{project}-{{version}}.tar.gz"
        ),
    )


def latest_bash() -> tuple[str, str]:
    # Only tarballs with the official patches rolled in (5.2.37); a bare
    # x.y release would need each patch pinned separately.
    return latest_from_index(
        "https://ftp.gnu.org/gnu/bash/",
        r"bash-(\d+\.\d+\.\d+)\.tar\.gz\"",
        "https://ftp.gnu.org/gnu/bash/bash-{version}.tar.gz",
    )


def latest_testssl() -> tuple[str, str]:
    # Stable tags only, not the 3.3dev snapshots.
    return latest_from_github_tags(
        "testssl/testssl.sh",
        r"v(\d+\.\d+\.\d+)",
        "https://github.com/testssl/testssl.sh/archive/refs/tags/v{version}.tar.gz",
    )


def latest_libssh2() -> tuple[str, str]:
    return latest_from_index(
        "https://libssh2.org/download/",
        r"libssh2-(\d+\.\d+\.\d+)\.tar\.xz\"",
        "https://libssh2.org/download/libssh2-{version}.tar.xz",
    )


def latest_readline() -> tuple[str, str]:
    # Rolled-up tarballs only (8.2.13), as for bash.
    return latest_from_index(
        "https://ftp.gnu.org/gnu/readline/",
        r"readline-(\d+\.\d+\.\d+)\.tar\.gz\"",
        "https://ftp.gnu.org/gnu/readline/readline-{version}.tar.gz",
    )


def latest_lftp() -> tuple[str, str]:
    # Upstream's GitHub release, the same archive as lftp.yar.ru's, which
    # CircleCI could not reach.
    return latest_from_github_release(
        "lavv17/lftp",
        r"v(\d+\.\d+\.\d+)",
        "https://github.com/lavv17/lftp/releases/download/v{version}/lftp-{version}.tar.gz",
    )


def latest_expat() -> tuple[str, str]:
    # Tags spell the version with underscores: R_2_10_0.
    release = json.loads(
        text("https://api.github.com/repos/libexpat/libexpat/releases/latest")
    )
    match = re.fullmatch(r"R_(\d+)_(\d+)_(\d+)", release["tag_name"])
    if match is None:
        raise RuntimeError(f"unexpected expat release tag: {release['tag_name']}")
    version = ".".join(match.groups())
    return version, (
        "https://github.com/libexpat/libexpat/releases/download/"
        f"{release['tag_name']}/expat-{version}.tar.xz"
    )


def latest_aria2() -> tuple[str, str]:
    return latest_from_github_release(
        "aria2/aria2",
        r"release-(\d+\.\d+\.\d+)",
        (
            "https://github.com/aria2/aria2/releases/download/"
            "release-{version}/aria2-{version}.tar.xz"
        ),
    )


def latest_cifs_utils() -> tuple[str, str]:
    return latest_from_index(
        "https://download.samba.org/pub/linux-cifs/cifs-utils/",
        r"cifs-utils-(\d+\.\d+(?:\.\d+)?)\.tar\.bz2\"",
        "https://download.samba.org/pub/linux-cifs/cifs-utils/cifs-utils-{version}.tar.bz2",
    )


def latest_libtirpc() -> tuple[str, str]:
    return latest_from_index(
        "https://sourceforge.net/projects/libtirpc/rss?path=/libtirpc",
        r"libtirpc-(\d+\.\d+\.\d+)\.tar\.bz2",
        (
            "https://downloads.sourceforge.net/project/libtirpc/libtirpc/"
            "{version}/libtirpc-{version}.tar.bz2"
        ),
    )


def latest_nfs_utils() -> tuple[str, str]:
    return latest_from_index(
        "https://cdn.kernel.org/pub/linux/utils/nfs-utils/",
        r'href="(\d+\.\d+\.\d+)/"',
        (
            "https://cdn.kernel.org/pub/linux/utils/nfs-utils/"
            "{version}/nfs-utils-{version}.tar.xz"
        ),
    )


def latest_udpcast() -> tuple[str, str]:
    return latest_from_index(
        "https://udpcast.linux.lu/downloads.html",
        r"udpcast-(\d{8})\.tar\.gz",
        "https://udpcast.linux.lu/download/udpcast-{version}.tar.gz",
    )


def latest_partclone() -> tuple[str, str]:
    # Release tags are bare versions; it publishes no release archive.
    return latest_from_github_tags(
        "Thomas-Tsai/partclone",
        r"(\d+\.\d+\.\d+)",
        "https://github.com/Thomas-Tsai/partclone/archive/refs/tags/{version}.tar.gz",
    )


def latest_xxhash() -> tuple[str, str]:
    return latest_from_github_tags(
        "Cyan4973/xxHash",
        r"v(\d+\.\d+\.\d+)",
        "https://github.com/Cyan4973/xxHash/archive/refs/tags/v{version}.tar.gz",
    )


def latest_par2cmdline() -> tuple[str, str]:
    return latest_from_github_release(
        "Parchive/par2cmdline",
        r"v(\d+\.\d+\.\d+)",
        (
            "https://github.com/Parchive/par2cmdline/releases/download/"
            "v{version}/par2cmdline-{version}.tar.gz"
        ),
    )


def latest_zig(host: str) -> tuple[str, str]:
    index = json.loads(text("https://ziglang.org/download/index.json"))
    stable = [key for key in index if re.fullmatch(r"\d+\.\d+\.\d+", key)]
    version = max(stable, key=numeric_version)
    return version, index[version][host]["tarball"]


def latest_go(arch: str | None) -> tuple[str, str]:
    """The newest stable Go: a host toolchain for ARCH, or the source."""
    releases = json.loads(text("https://go.dev/dl/?mode=json"))
    release = max(
        (r for r in releases if r["stable"]),
        key=lambda r: numeric_version(r["version"].removeprefix("go")),
    )
    wanted = (
        {"kind": "archive", "os": "linux", "arch": arch}
        if arch
        else {"kind": "source"}
    )
    for item in release["files"]:
        if all(item[key] == value for key, value in wanted.items()):
            return (
                release["version"].removeprefix("go"),
                f"https://dl.google.com/go/{item['filename']}",
            )
    raise RuntimeError(f"no Go {arch or 'source'} archive in {release['version']}")


def latest_wireguard_go() -> tuple[str, str]:
    return latest_from_github_tags(
        "WireGuard/wireguard-go",
        r"(\d+\.\d+\.\d+)",
        (
            "https://github.com/WireGuard/wireguard-go/archive/refs/tags/"
            "{version}.tar.gz"
        ),
    )


def latest_sqlite() -> tuple[str, str]:
    # The download page lists each product in a comment for scripts; the
    # autoconf amalgamation's URL carries the release year and an encoded
    # version (3.54.1 is 3540100).
    index = text("https://sqlite.org/download.html")
    match = re.search(
        r"PRODUCT,(\d+\.\d+\.\d+),(\d{4}/sqlite-autoconf-\d+\.tar\.gz),", index
    )
    if match is None:
        raise RuntimeError("no sqlite-autoconf release found")
    return match.group(1), f"https://sqlite.org/{match.group(2)}"


def latest_quickjs() -> tuple[str, str]:
    return latest_from_github_tags(
        "quickjs-ng/quickjs",
        r"v(\d+\.\d+\.\d+)",
        "https://github.com/quickjs-ng/quickjs/archive/refs/tags/v{version}.tar.gz",
    )


def latest_lua() -> tuple[str, str]:
    return latest_from_index(
        "https://www.lua.org/ftp/",
        r"lua-(\d+\.\d+\.\d+)\.tar\.gz",
        "https://www.lua.org/ftp/lua-{version}.tar.gz",
    )


def latest_htop() -> tuple[str, str]:
    return latest_from_github_release(
        "htop-dev/htop",
        r"(\d+\.\d+\.\d+)",
        "https://github.com/htop-dev/htop/releases/download/{version}/htop-{version}.tar.xz",
    )


def latest_make() -> tuple[str, str]:
    return latest_from_index(
        "https://ftp.gnu.org/gnu/make/",
        r"make-(\d+\.\d+(?:\.\d+)?)\.tar\.gz\"",
        "https://ftp.gnu.org/gnu/make/make-{version}.tar.gz",
    )


def latest_rclone() -> tuple[str, str]:
    return latest_from_github_release(
        "rclone/rclone",
        r"v(\d+\.\d+\.\d+)",
        (
            "https://github.com/rclone/rclone/releases/download/"
            "v{version}/rclone-v{version}.tar.gz"
        ),
    )


def latest_croc() -> tuple[str, str]:
    return latest_from_github_release(
        "schollz/croc",
        r"v(\d+\.\d+\.\d+)",
        (
            "https://github.com/schollz/croc/releases/download/"
            "v{version}/croc_v{version}_src.tar.gz"
        ),
    )


def latest_cri_tools() -> tuple[str, str]:
    return latest_from_github_tags(
        "kubernetes-sigs/cri-tools",
        r"v(\d+\.\d+\.\d+)",
        (
            "https://github.com/kubernetes-sigs/cri-tools/archive/refs/tags/"
            "v{version}.tar.gz"
        ),
    )


def latest_containerd() -> tuple[str, str]:
    return latest_from_github_tags(
        "containerd/containerd",
        r"v(\d+\.\d+\.\d+)",
        (
            "https://github.com/containerd/containerd/archive/refs/tags/"
            "v{version}.tar.gz"
        ),
    )


# Checksum files published beside a release: a candidate archive whose
# SHA-256 is not listed there is rejected. rclone's file is also PGP-signed;
# reviewers check that signature (CONTRIBUTING.md).
PUBLISHED_SHA256: dict[str, str] = {
    "zstd": (
        "https://github.com/meta/zstd/releases/download/"
        "v{version}/zstd-{version}.tar.gz.sha256"
    ),
    "rclone": "https://github.com/rclone/rclone/releases/download/v{version}/SHA256SUMS",
    "croc": (
        "https://github.com/schollz/croc/releases/download/"
        "v{version}/croc_v{version}_checksums.txt"
    ),
    "stunnel": "https://www.stunnel.org/downloads/stunnel-{version}.tar.gz.sha256",
    "nfs-utils": "https://cdn.kernel.org/pub/linux/utils/nfs-utils/{version}/sha256sums.asc",
}


DISCOVERERS: dict[str, Callable[[], tuple[str, str]]] = {
    "busybox": latest_busybox,
    "socat": latest_socat,
    "dropbear": latest_dropbear,
    "iproute2": latest_iproute2,
    "wireguard-tools": latest_wireguard_tools,
    "openssl": latest_openssl,
    "libpcap": latest_libpcap,
    "libmnl": latest_libmnl,
    "libcap-ng": latest_libcap_ng,
    "tcpdump": latest_tcpdump,
    "curl": latest_curl,
    "iperf3": latest_iperf3,
    "ethtool": latest_ethtool,
    "strace": latest_strace,
    "jq": latest_jq,
    "ldns": latest_ldns,
    "mtr": latest_mtr,
    "can-utils": latest_can_utils,
    "i2c-tools": latest_i2c_tools,
    "spi-tools": latest_spi_tools,
    "nmap": latest_nmap,
    "rsync": latest_rsync,
    "lsof": latest_lsof,
    "util-linux": latest_util_linux,
    "ppp": latest_ppp,
    "picocom": latest_picocom,
    "lrzsz": latest_lrzsz,
    "gdb": latest_gdb,
    "openssh": latest_openssh,
    "libnfnetlink": lambda: latest_netfilter("libnfnetlink", "bz2"),
    "libnetfilter_conntrack": lambda: latest_netfilter(
        "libnetfilter_conntrack", "xz"
    ),
    "conntrack-tools": lambda: latest_netfilter("conntrack-tools", "xz"),
    "ipmitool": latest_ipmitool,
    "mtd-utils": latest_mtd_utils,
    "libnl": latest_libnl,
    "iw": latest_iw,
    "zlib": latest_zlib,
    "bzip2": latest_bzip2,
    "xz": latest_xz,
    "zstd": latest_zstd,
    "pigz": latest_pigz,
    "pv": latest_pv,
    "mbuffer": latest_mbuffer,
    "libarchive": latest_libarchive,
    "kmod": latest_kmod,
    "kexec-tools": latest_kexec_tools,
    "elfutils": latest_elfutils,
    "bpftool": latest_bpftool,
    "iputils": latest_iputils,
    "traceroute": latest_traceroute,
    "ndisc6": latest_ndisc6,
    "lldpd": latest_lldpd,
    "ipset": lambda: latest_netfilter_pub("ipset", r"\d+\.\d+", "bz2"),
    "iptables": lambda: latest_netfilter("iptables", "xz"),
    "ebtables": lambda: latest_netfilter_pub("ebtables", r"\d+\.\d+\.\d+", "gz"),
    "arptables": lambda: latest_netfilter_pub("arptables", r"\d+\.\d+\.\d+", "gz"),
    "ngrep": latest_ngrep,
    "hping3": lambda: latest_hping3("orig"),
    "hping3-debian": lambda: latest_hping3("debian"),
    "ncurses": latest_ncurses,
    "iftop": latest_iftop,
    "nethogs": latest_nethogs,
    "tcpreplay": latest_tcpreplay,
    "dhcpdump": latest_dhcpdump,
    "libevent": latest_libevent,
    "tmux": latest_tmux,
    "stunnel": latest_stunnel,
    "openvpn": latest_openvpn,
    "microsocks": latest_microsocks,
    "tinyproxy": latest_tinyproxy,
    "dnsmasq": latest_dnsmasq,
    "libyaml": latest_libyaml,
    "gensio": lambda: latest_cminyard("gensio"),
    "ser2net": lambda: latest_cminyard("ser2net"),
    "bash": latest_bash,
    "testssl.sh": latest_testssl,
    "libssh2": latest_libssh2,
    "readline": latest_readline,
    "lftp": latest_lftp,
    "expat": latest_expat,
    "aria2": latest_aria2,
    "cifs-utils": latest_cifs_utils,
    "libtirpc": latest_libtirpc,
    "nfs-utils": latest_nfs_utils,
    "udpcast": latest_udpcast,
    "partclone": latest_partclone,
    "xxhash": latest_xxhash,
    "par2cmdline": latest_par2cmdline,
    "sqlite": latest_sqlite,
    "quickjs": latest_quickjs,
    "lua": latest_lua,
    "htop": latest_htop,
    "make": latest_make,
    "zig-x86_64": lambda: latest_zig("x86_64-linux"),
    "zig-aarch64": lambda: latest_zig("aarch64-linux"),
    "go-x86_64": lambda: latest_go("amd64"),
    "go-aarch64": lambda: latest_go("arm64"),
    "go": lambda: latest_go(None),
    "wireguard-go": latest_wireguard_go,
    "rclone": latest_rclone,
    "croc": latest_croc,
    "cri-tools": latest_cri_tools,
    "containerd": latest_containerd,
}


def parse_lock(path: Path) -> tuple[list[str], dict[str, Source]]:
    lines = path.read_text(encoding="utf-8").splitlines()
    sources: dict[str, Source] = {}
    for line in lines:
        if not line or line.startswith("#"):
            continue
        fields = line.split("|")
        if len(fields) != 4:
            raise RuntimeError(f"invalid lock record: {line}")
        source = Source(*fields)
        if source.name in sources:
            raise RuntimeError(f"duplicate source: {source.name}")
        sources[source.name] = source
    return lines, sources


def sha256_url(url: str) -> str:
    digest = hashlib.sha256()
    with request(url) as response:
        while chunk := response.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def render(lines: list[str], replacements: dict[str, Source]) -> str:
    rendered: list[str] = []
    for line in lines:
        name = line.split("|", 1)[0]
        source = replacements.get(name)
        if source is None:
            rendered.append(line)
        else:
            rendered.append(
                "|".join((source.name, source.version, source.sha256, source.url))
            )
    return "\n".join(rendered) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true", help="update sources.lock")
    parser.add_argument(
        "--check",
        action="store_true",
        help="exit 1 when a newer release exists",
    )
    parser.add_argument(
        "--only",
        action="append",
        choices=sorted(DISCOVERERS),
        help="check only one source (repeatable)",
    )
    args = parser.parse_args()

    lines, sources = parse_lock(LOCK_PATH)
    selected = args.only or list(DISCOVERERS)
    replacements: dict[str, Source] = {}

    for name in selected:
        current = sources.get(name)
        if current is None:
            raise RuntimeError(f"{name} is not present in {LOCK_PATH}")
        version, url = DISCOVERERS[name]()
        numeric_release = r"\d+(?:\.\d+)*"
        if (
            re.fullmatch(numeric_release, version)
            and re.fullmatch(numeric_release, current.version)
            and numeric_version(version) < numeric_version(current.version)
        ):
            raise RuntimeError(
                f"upstream version for {name} went backwards: "
                f"{current.version} -> {version}"
            )
        if version == current.version and url == current.url:
            print(f"{name}: current ({current.version})")
            continue

        print(f"{name}: {current.version} -> {version}; downloading for SHA-256")
        digest = sha256_url(url)
        if name in PUBLISHED_SHA256:
            sums_url = PUBLISHED_SHA256[name].format(version=version)
            if f"{digest}  {url.rsplit('/', 1)[1]}" not in text(sums_url).splitlines():
                raise RuntimeError(f"{url} is not listed with SHA-256 {digest} in {sums_url}")
        replacements[name] = Source(name, version, digest, url)

    if not replacements:
        print("all selected sources are current")
        return 0

    if args.write:
        LOCK_PATH.write_text(render(lines, replacements), encoding="utf-8")
        print(f"updated {LOCK_PATH}")
        return 0

    print("updates available; rerun with --write")
    return 1 if args.check else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(2)
