#!/usr/bin/env python3
"""Pack CPython's standard library into the zip its interpreter imports from.

Usage: python-stdlib-zip.py LIB_DIR OUTPUT

Sources and the bytecode compiled beside them (legacy NAME.pyc, the only
place zipimport looks), in sorted order with one fixed timestamp, so the
archive is reproducible. Left out: the test suites, IDLE, tkinter and turtle
(no Tk), and ensurepip (no pip).
"""

import sys
import zipfile
from pathlib import Path

PRUNE = {
    "test",
    "tests",
    "idlelib",
    "tkinter",
    "turtledemo",
    "ensurepip",
    "__pycache__",
    "site-packages",
}
SKIP_FILES = {"turtle.py", "turtle.pyc"}
# The earliest date the zip format can hold.
EPOCH = (1980, 1, 1, 0, 0, 0)


def add(archive: zipfile.ZipFile, source: Path, name: str) -> None:
    info = zipfile.ZipInfo(name, EPOCH)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o644 << 16
    archive.writestr(info, source.read_bytes(), compresslevel=9)


def main() -> None:
    lib, output = (Path(argument) for argument in sys.argv[1:3])
    files = [
        path
        for path in lib.rglob("*")
        if path.is_file()
        and path.name not in SKIP_FILES
        and not PRUNE.intersection(path.relative_to(lib).parts)
    ]
    with zipfile.ZipFile(output, "w") as archive:
        for path in sorted(files, key=lambda p: p.relative_to(lib).as_posix()):
            add(archive, path, path.relative_to(lib).as_posix())


if __name__ == "__main__":
    main()
