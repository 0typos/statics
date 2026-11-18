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
        install -m 0755 "$REPO_ROOT/configs/testssl.sh" "$OUTPUT_DIR/testssl.sh"
    )
}
