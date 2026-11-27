#!/usr/bin/env bash

# Upstream's own main with all standard modules. components.tsv builds it
# with the tags upstream's CI uses (nobadger, nomysql, nopgx), which drop
# database backends of the internal CA that no standard module configures.
# A trimmed main (reverse proxy, file server, TLS, and PKI only) was measured
# at 47 MB against 51 MB, so it is not worth diverging from upstream.
build_caddy() {
    echo "==> building caddy"
    go_build caddy ./cmd/caddy caddy \
        "-X github.com/caddyserver/caddy/v2.CustomVersion=v$(source_version caddy)" ||
        return 1
    # Caddy's files that adapt third-party code name its authors and terms
    # only in comments; collect those lines, as there is no notice file.
    (
        cd "$WORK_DIR/caddy" || exit
        grep -HiE 'copyright|licen[cs]e|borrowed|adapted from' \
            modules/caddyhttp/reverseproxy/ascii.go \
            modules/caddyhttp/reverseproxy/streaming.go \
            modules/caddyhttp/reverseproxy/fastcgi/client.go \
            modules/caddyhttp/reverseproxy/fastcgi/fastcgi.go \
            modules/caddyhttp/encode/encode.go \
            modules/caddytls/ech.go > CADDY-NOTICES
        local author
        for author in 'The Go Authors' 'Dunglas' 'Httpgzip Authors' 'Omar Tariq'; do
            grep -q "$author" CADDY-NOTICES || {
                echo "CADDY-NOTICES lacks the notice of $author" >&2
                exit 1
            }
        done
    )
}
