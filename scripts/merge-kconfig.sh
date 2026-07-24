#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 CONFIG FRAGMENT" >&2
    exit 2
fi

config=$1
fragment=$2

while IFS= read -r line; do
    case "$line" in
        CONFIG_*=*)
            symbol=${line%%=*}
            ;;
        "# CONFIG_"*" is not set")
            symbol=${line#\# }
            symbol=${symbol% is not set}
            ;;
        ""|"#"*)
            continue
            ;;
        *)
            echo "unsupported config fragment line: $line" >&2
            exit 1
            ;;
    esac

    sed -i -e "/^${symbol}=/d" -e "/^# ${symbol} is not set$/d" "$config"
    printf '%s\n' "$line" >> "$config"
done < "$fragment"
