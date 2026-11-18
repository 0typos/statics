#!/bin/sh
# testssl.sh from the statics bundle: upstream's script in share/testssl/,
# run by the bundled bash with the bundled openssl and, for DNS, drill.
# BusyBox's hexdump, grep, awk, and sed, which testssl.sh accepts, fill in
# for any the host lacks. It still needs the host's dd, tr, wc, date, cat,
# ps, kill, head, tail, and dirname, and refuses BusyBox's: see
# docs/TOOLKIT.md.
dir=$(dirname "$(readlink -f "$0")") || exit 1
PATH=$dir:$PATH:$dir/share/testssl/bin
OPENSSL=$dir/openssl
TESTSSL_INSTALL_DIR=$dir/share/testssl
export PATH OPENSSL TESTSSL_INSTALL_DIR
exec "$dir/bash" "$dir/share/testssl/testssl.sh" "$@"
