#!/usr/bin/env bash
# Functional test for tunpipe: two network namespaces joined by a tunpipe pair
# over a socketpair, inside an unprivileged user namespace.
#
# Usage: test-tunpipe.sh DIR   (DIR holds a tunpipe executable or link)
# Needs unprivileged user namespaces plus ip, nft, unshare, nsenter and busybox
# in DIR or on PATH, so a built dist/ARCH directory is enough; exits 77 (skip) when user namespaces are unavailable, as in most
# containers.
set -euo pipefail

if [[ $# -ne 1 || ! -x $1/tunpipe ]]; then
    echo "usage: $0 DIR_WITH_TUNPIPE" >&2
    exit 2
fi
dir=$(cd "$1" && pwd)

if [[ ${TUNPIPE_TEST_INNER:-} != 1 ]]; then
    if ! unshare -rnm true 2>/dev/null; then
        echo "SKIP: unprivileged user namespaces are unavailable" >&2
        exit 77
    fi
    TUNPIPE_TEST_INNER=1 PATH="$dir:$PATH" exec unshare -rnm "$0" "$dir"
fi

# Inside: root in a fresh user, network and mount namespace.
ping=(busybox ping)
mount -t tmpfs tmpfs /run
ip link set lo up

pids=()
trap 'kill "${pids[@]}" 2>/dev/null || true' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

wait_until() { # tries, command...
    local tries=$1
    shift
    while ! "$@" >/dev/null 2>&1; do
        ((--tries > 0)) || return 1
        sleep 0.1
    done
}

# The server end runs in its own namespace with 10.99.0.1 on lo, reachable only
# through the tunnel.
server='ip link set lo up && ip addr add 10.99.0.1/32 dev lo && exec tunpipe -l 10.9.0.1 -p 10.9.0.2 "$@"'

server_pid() { # the server is the client tunpipe's only child
    tr -d ' ' <"/proc/$1/task/$1/children"
}

exits_within() { # seconds, pid, status: the pid must exit with status in time
    local tries=$(($1 * 10)) status=0
    while kill -0 "$2" 2>/dev/null; do
        ((--tries > 0)) || fail "tunpipe still running after $1 s"
        sleep 0.1
    done
    wait "$2" || status=$?
    [[ $status -eq $3 ]] || fail "tunpipe exited $status, want $3"
}

stop() { # pid; tunpipe must exit 143 on SIGTERM, promptly
    kill "$1"
    exits_within 5 "$1" 143
}

echo "== subnet route and NAT"
tunpipe -l 10.9.0.2 -p 10.9.0.1 -r 10.99.0.0/24 -- \
    unshare -n sh -c "$server" sh -N &
pids+=($!)
client=$!
wait_until 50 "${ping[@]}" -c 1 -W 1 10.9.0.1 || fail "peer address unreachable"
"${ping[@]}" -c 3 -W 1 10.99.0.1 >/dev/null || fail "routed subnet unreachable"
ip route show 10.99.0.0/24 | grep -q 'dev tp0' || fail "subnet route not on tp0"
spid=$(server_pid "$client")
nsenter -t "$spid" -n nft list table ip tunpipe_tp0 | grep -q masquerade ||
    fail "server NAT table missing"
[[ $(nsenter -t "$spid" -n cat /proc/sys/net/ipv4/ip_forward) == 1 ]] ||
    fail "server did not enable forwarding"
stop "$client"
! ip link show tp0 >/dev/null 2>&1 || fail "tp0 left behind"
! nsenter -t "$spid" -n true 2>/dev/null || fail "server outlived the client"

echo "== default route in a named netns"
tunpipe -n tptest -l 10.9.0.2 -p 10.9.0.1 -- unshare -n sh -c "$server" sh &
pids+=($!)
client=$!
wait_until 50 nsenter --net=/run/netns/tptest "${ping[@]}" -c 1 -W 1 10.99.0.1 ||
    fail "default route through the netns tunnel failed"
! ip link show tp0 >/dev/null 2>&1 || fail "tunnel leaked into the host namespace"
stop "$client"
[[ ! -e /run/netns/tptest ]] || fail "/run/netns/tptest left behind"

echo "== SIGTERM while the stream is saturated"
# The server streams zeros to the client; stopping the client must not hang
# either end in a blocked write or wait.
loaded='busybox timeout -s KILL 20 busybox nc -l -p 9 </dev/zero >/dev/null & '"$server"
tunpipe -l 10.9.0.2 -p 10.9.0.1 -r 10.99.0.0/24 -- unshare -n sh -c "$loaded" sh &
pids+=($!)
client=$!
wait_until 50 "${ping[@]}" -c 1 -W 1 10.99.0.1 || fail "tunnel did not come up"
busybox nc 10.99.0.1 9 >/dev/null &
pids+=($!)
sleep 1
rx_bytes=$(awk -F "[: ]+" "/tp0:/ { print \$3 }" /proc/net/dev)
((rx_bytes > 1000000)) || fail "no load reached the client ($rx_bytes bytes)"
stop "$client"
! ip link show tp0 >/dev/null 2>&1 || fail "tp0 left behind"

echo "== exits when its interface is deleted"
tunpipe -l 10.9.0.2 -p 10.9.0.1 -- unshare -n sh -c "$server" sh &
pids+=($!)
client=$!
wait_until 50 "${ping[@]}" -c 1 -W 1 10.9.0.1 || fail "tunnel did not come up"
ip link del tp0
exits_within 5 "$client" 1

echo "== refuses a peer that is not tunpipe"
status=0
out=$(tunpipe -l 10.9.0.2 -p 10.9.0.1 -- sh -c 'echo Welcome to host; cat >/dev/null' 2>&1) ||
    status=$?
[[ $status -eq 1 && $out == *"not tunpipe"* ]] || fail "banner not rejected ($status): $out"
! ip link show tp0 >/dev/null 2>&1 || fail "tp0 left behind after rejection"

echo "PASS"
