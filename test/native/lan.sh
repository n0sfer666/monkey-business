#!/bin/sh
set -eu
cleanup() { ip netns del mb-lan-client 2>/dev/null || true; ip link del mb-lan-router 2>/dev/null || true; }
trap cleanup EXIT
# This disposable VM's stock fw4 knows only br-lan, not the synthetic veth.
# Remove that fixture-only unrelated zone policy; both production application
# tables (diagnostic guard and TPROXY) remain installed and are exercised together.
nft delete table inet fw4 2>/dev/null || true
ip netns add mb-lan-client
ip link add mb-lan-router type veth peer name mb-lan-peer
ip link set mb-lan-peer netns mb-lan-client
ip addr add 10.19.0.1/24 dev mb-lan-router
ip link set mb-lan-router up
ip -n mb-lan-client link set lo up
ip -n mb-lan-client addr add 10.19.0.2/24 dev mb-lan-peer
ip -n mb-lan-client link set mb-lan-peer up
ip -n mb-lan-client route add default via 10.19.0.1
/etc/init.d/dnsmasq stop
/tmp/mb-relay-client dns-server >/tmp/mb-lan-dns.log 2>&1 &
dns_pid=$!
trap 'kill "$dns_pid" 2>/dev/null || true; wait "$dns_pid" 2>/dev/null || true; cleanup' EXIT
ucode /tmp/mb-native/test/native/lan.uc
