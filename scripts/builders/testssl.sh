#!/usr/bin/env bash

build_testssl() {
    echo "==> installing testssl.sh"
    (
        cd "$WORK_DIR/testssl.sh" || exit
        # Upstream's script, unmodified, with the data it reads. Of its
        # trust stores only Mozilla's: the Apple, Java, Linux, and
        # Microsoft stores would add about 1.6 MB (900 kB compressed).
        # --add-ca or ADDTL_CA_FILES adds others at run time.
        local file
        install -D -m 0755 testssl.sh "$OUTPUT_DIR/share/testssl/testssl.sh"
        for file in Mozilla.pem ca_hashes.txt cipher-mapping.txt \
            client-simulation.txt common-primes.txt openssl.cnf tls_data.txt; do
            install_output_file "etc/$file" "share/testssl/etc/$file"
        done
        # BusyBox applets testssl.sh accepts, last in the wrapper's PATH.
        mkdir -p "$OUTPUT_DIR/share/testssl/bin"
        for file in hexdump grep awk sed; do
            ln -s ../../../busybox "$OUTPUT_DIR/share/testssl/bin/$file"
        done
        install -m 0755 "$REPO_ROOT/configs/testssl.sh" "$OUTPUT_DIR/testssl.sh"
        # The script's own license statement, including the client
        # simulation data's CC BY 3.0 US terms and Qualys SSL Labs
        # attribution, and the trust store's MPL-2.0 source.
        {
            echo "From testssl.sh's header:"
            sed -n '/^# License: GPLv2/,/creativecommons.org\/licenses\/by\/3.0\/us/p' testssl.sh
            echo
            echo "From etc/README.md (only the Mozilla store is shipped, as etc/Mozilla.pem):"
            grep -F '**Mozilla:**' etc/README.md
        } > TESTSSL-NOTICES
        if ! grep -q 'Qualys SSL Labs' TESTSSL-NOTICES ||
            ! grep -q 'MPL 2.0' TESTSSL-NOTICES; then
            echo "TESTSSL-NOTICES lacks the data licenses" >&2
            exit 1
        fi
    )
}
