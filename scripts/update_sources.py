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
            "https://mirrors.edge.kernel.org/pub/linux/utils/net/iproute2/"
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
            "https://mirrors.edge.kernel.org/pub/software/network/ethtool/"
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
            "https://mirrors.edge.kernel.org/pub/software/utils/i2c-tools/"
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


def latest_zig(host: str) -> tuple[str, str]:
    index = json.loads(text("https://ziglang.org/download/index.json"))
    stable = [key for key in index if re.fullmatch(r"\d+\.\d+\.\d+", key)]
    version = max(stable, key=numeric_version)
    return version, index[version][host]["tarball"]


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
    "zig-x86_64": lambda: latest_zig("x86_64-linux"),
    "zig-aarch64": lambda: latest_zig("aarch64-linux"),
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
        replacements[name] = Source(name, version, sha256_url(url), url)

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
