#!/usr/bin/env bash
# Compare two packaged builds of the same architecture byte for byte.
#
# package.sh is deterministic (sorted entries, fixed mtime and owner), so equal
# archives mean equal trees, modes, and symlinks. On a mismatch both archives
# are unpacked and diffed so the log names what differs.
#
# Usage: compare-builds.sh EXPECTED.tar.xz ACTUAL.tar.xz
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 EXPECTED.tar.xz ACTUAL.tar.xz" >&2
    exit 2
fi

expected=$1
actual=$2

if cmp --quiet "$expected" "$actual"; then
    echo "identical: $(sha256sum "$expected" | cut -d ' ' -f 1)"
    exit 0
fi

echo "archives differ:" >&2
sha256sum "$expected" "$actual" >&2

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/expected" "$work/actual"
tar -xJf "$expected" -C "$work/expected"
tar -xJf "$actual" -C "$work/actual"
diff --recursive --no-dereference "$work/expected" "$work/actual" >&2 ||
    true
# Trees can match while metadata differs; list entries to expose that too.
diff <(tar -tvJf "$expected") <(tar -tvJf "$actual") >&2 || true
exit 1
