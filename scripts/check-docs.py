#!/usr/bin/env python3
"""Validate repository Markdown structure and local links."""

from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parent.parent
LINK = re.compile(
    r"""!?\[[^\]]*]\((?P<target><[^>]+>|[^)\s]+)(?:\s+["'][^)]*["'])?\)"""
)
EXTERNAL_SCHEMES = {"http", "https", "mailto"}


def markdown_files() -> list[Path]:
    root_docs = (
        ROOT / "README.md",
        ROOT / "CONTRIBUTING.md",
        ROOT / "SECURITY.md",
    )
    files = [path for path in root_docs if path.exists()]
    files.extend(sorted((ROOT / "docs").glob("*.md")))
    return files


def check_file(path: Path) -> list[str]:
    relative = path.relative_to(ROOT)
    text = path.read_text(encoding="utf-8")
    errors: list[str] = []

    if not text.startswith("# "):
        errors.append(f"{relative}:1: document must start with an H1")
    if not text.endswith("\n"):
        errors.append(f"{relative}: document must end with a newline")

    for line_number, line in enumerate(text.splitlines(), start=1):
        if line.endswith((" ", "\t")):
            errors.append(f"{relative}:{line_number}: trailing whitespace")

    for match in LINK.finditer(text):
        target = match.group("target").strip("<>")
        parsed = urlsplit(target)
        if parsed.scheme in EXTERNAL_SCHEMES or target.startswith("#"):
            continue
        if parsed.scheme or parsed.netloc:
            errors.append(f"{relative}: unsupported link target: {target}")
            continue

        link_path = unquote(parsed.path)
        if not link_path:
            continue
        destination = (path.parent / link_path).resolve()
        try:
            destination.relative_to(ROOT)
        except ValueError:
            errors.append(f"{relative}: local link escapes repository: {target}")
            continue
        if not destination.exists():
            errors.append(f"{relative}: broken local link: {target}")

    return errors


def main() -> int:
    files = markdown_files()
    errors = [error for path in files for error in check_file(path)]
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"documentation is valid ({len(files)} files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
