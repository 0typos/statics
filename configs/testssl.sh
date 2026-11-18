#!/bin/sh
# testssl.sh from the statics bundle: upstream's script in share/testssl/,
# run by the bundled bash with the bundled openssl, and drill for DNS where
# the host has neither dig nor host.
# BusyBox's hexdump, grep, awk, and sed, which testssl.sh accepts, fill in
# for any the host lacks. It still needs the host's dd, tr, wc, date, cat,
# ps, kill, head, tail, and dirname, and refuses BusyBox's: see
# docs/TOOLKIT.md.
# Without an absolute path for itself it would run ./bash from the
# current directory, so refuse instead.
target=$(readlink -f -- "$0") || exit 1
case $target in
    /*) dir=${target%/*} ;;
    *) echo "testssl.sh: cannot resolve $0" >&2; exit 1 ;;
esac
PATH=$dir:$PATH:$dir/share/testssl/bin
OPENSSL=$dir/openssl
TESTSSL_INSTALL_DIR=$dir/share/testssl
export PATH OPENSSL TESTSSL_INSTALL_DIR
exec "$dir/bash" "$dir/share/testssl/testssl.sh" "$@"
