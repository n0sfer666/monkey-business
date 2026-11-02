#!/bin/sh
set -eu
# Both namespaces exist only inside the disposable snapshot VM.
cleanup() {
 kill "${direct_pid:-}" 2>/dev/null || true
 wait "${direct_pid:-}" 2>/dev/null || true
 ip netns del mb-apply-client 2>/dev/null || true
 ip netns del mb-direct 2>/dev/null || true
 ip link del mb-apply-router 2>/dev/null || true
 ip link del mb-direct-rtr 2>/dev/null || true
}
trap cleanup EXIT
nft delete table inet fw4 2>/dev/null || true
ip netns add mb-apply-client
ip link add mb-apply-router type veth peer name mb-apply-peer
ip link set mb-apply-peer netns mb-apply-client
ip addr add 10.19.1.1/24 dev mb-apply-router
ip link set mb-apply-router up
ip -n mb-apply-client link set lo up
ip -n mb-apply-client addr add 10.19.1.2/24 dev mb-apply-peer
ip -n mb-apply-client link set mb-apply-peer up
ip -n mb-apply-client route add default via 10.19.1.1
ip netns add mb-direct
ip link add mb-direct-rtr type veth peer name mb-direct-peer
ip link set mb-direct-peer netns mb-direct
ip addr add 8.8.8.1/24 dev mb-direct-rtr
ip link set mb-direct-rtr up
ip -n mb-direct link set lo up
ip -n mb-direct addr add 8.8.8.8/24 dev mb-direct-peer
ip -n mb-direct link set mb-direct-peer up
ip -n mb-direct route add default via 8.8.8.1
ip netns exec mb-direct /tmp/mb-relay-client direct-server >/tmp/mb-direct-contacts 2>&1 &
direct_pid=$!
sleep 1
# Negative control proves a genuine direct path is reachable before activation.
status=$(ip netns exec mb-apply-client curl --disable --noproxy '*' -s --max-time 1 -o /dev/null -w '%{http_code}' http://8.8.8.8:18081/)
[ "$status" = 200 ]
printf '' >/tmp/mb-direct-contacts
ucode /tmp/mb-native/test/native/apply.uc
