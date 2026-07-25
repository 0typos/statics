#!/usr/bin/env python3
"""Generate a deterministic SPDX 2.3 JSON SBOM for one architecture bundle."""

from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def spdx_id(prefix: str, value: str) -> str:
    normalized = re.sub(r"[^A-Za-z0-9.-]+", "-", value).strip("-")
    return f"SPDXRef-{prefix}-{normalized}"


def records(path: Path) -> list[list[str]]:
    result: list[list[str]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        result.append(line.split("|"))
    return result


def checksum(path: Path, algorithm: str) -> str:
    digest = hashlib.new(algorithm)
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} OUTPUT_DIR ARCH", file=sys.stderr)
        return 2

    output_dir = Path(sys.argv[1]).resolve()
    arch = sys.argv[2]
    source_records = {
        fields[0]: fields for fields in records(ROOT / "sources.lock")
    }
    components = records(ROOT / "components.tsv")
    lock_digest = hashlib.sha256(
        (ROOT / "sources.lock").read_bytes()
    ).hexdigest()

    bundle_id = spdx_id("Package", f"statics-{arch}")
    bundle_package: dict[str, object] = {
        "SPDXID": bundle_id,
        "name": f"statics-{arch}",
        "versionInfo": lock_digest[:16],
        "downloadLocation": "NOASSERTION",
        "filesAnalyzed": True,
        "licenseConcluded": "NOASSERTION",
        "licenseDeclared": "NOASSERTION",
        "copyrightText": "NOASSERTION",
        "primaryPackagePurpose": "APPLICATION",
    }
    packages: list[dict[str, object]] = [bundle_package]
    relationships: list[dict[str, str]] = [
        {
            "spdxElementId": "SPDXRef-DOCUMENT",
            "relationshipType": "DESCRIBES",
            "relatedSpdxElement": bundle_id,
        }
    ]

    for source_name, license_expression, _role in components:
        name, version, sha256, url = source_records[source_name]
        package_id = spdx_id("Package", source_name)
        packages.append(
            {
                "SPDXID": package_id,
                "name": name,
                "versionInfo": version,
                "downloadLocation": url,
                "filesAnalyzed": False,
                "checksums": [
                    {"algorithm": "SHA256", "checksumValue": sha256}
                ],
                "licenseConcluded": "NOASSERTION",
                "licenseDeclared": license_expression,
                "copyrightText": "NOASSERTION",
                "primaryPackagePurpose": "LIBRARY",
            }
        )
        relationships.append(
            {
                "spdxElementId": bundle_id,
                "relationshipType": "DEPENDS_ON",
                "relatedSpdxElement": package_id,
            }
        )

    files: list[dict[str, object]] = []
    file_sha1_checksums: list[str] = []
    sums_path = output_dir / "SHA256SUMS"
    for line in sums_path.read_text(encoding="utf-8").splitlines():
        sha256, filename = line.split(maxsplit=1)
        filename = filename.lstrip("*")
        sha1 = checksum(output_dir / filename, "sha1")
        file_sha1_checksums.append(sha1)
        file_id = spdx_id("File", filename)
        files.append(
            {
                "SPDXID": file_id,
                "fileName": f"./{filename}",
                "checksums": [
                    {"algorithm": "SHA1", "checksumValue": sha1},
                    {"algorithm": "SHA256", "checksumValue": sha256},
                ],
                "licenseConcluded": "NOASSERTION",
                "copyrightText": "NOASSERTION",
            }
        )
        relationships.append(
            {
                "spdxElementId": bundle_id,
                "relationshipType": "CONTAINS",
                "relatedSpdxElement": file_id,
            }
        )

    verification_input = "".join(sorted(file_sha1_checksums)).encode("ascii")
    bundle_package["packageVerificationCode"] = {
        "packageVerificationCodeValue": hashlib.sha1(
            verification_input
        ).hexdigest()
    }

    document = {
        "spdxVersion": "SPDX-2.3",
        "dataLicense": "CC0-1.0",
        "SPDXID": "SPDXRef-DOCUMENT",
        "name": f"statics-{arch}",
        "documentNamespace": (
            "https://spdx.org/spdxdocs/"
            f"statics-{arch}-{lock_digest}"
        ),
        "creationInfo": {
            "created": "1970-01-01T00:00:00Z",
            "creators": ["Tool: statics-generate-sbom"],
            "licenseListVersion": "3.27",
        },
        "packages": packages,
        "files": files,
        "relationships": relationships,
    }
    destination = output_dir / "SBOM.spdx.json"
    destination.write_text(
        json.dumps(document, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
