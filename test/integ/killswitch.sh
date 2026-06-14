#!/bin/sh
# Kill-switch leak-guard (scripts/firewall/apply.sh, MB_KILL_SWITCH).
# Симулирует "TPROXY не перехватил" (Xray упал / дыра в правилах): сбрасываем prerouting-redirect
# и проверяем, что форвардимый LAN->non-private трафик ДРОПается (kill_switch=1) и НЕ дропается,
# а форвардится (kill_switch=0). Топология: client(mbc) --vr-- router(mbr) --dum0(внешняя сеть).
set -u

NS_R=mbr
NS_C=mbc
EXT=198.51.100.1     # TEST-NET-2 (внешний адрес "за роутером")

cleanup() {
	ip netns del "$NS_R" 2>/dev/null || true
	ip netns del "$NS_C" 2>/dev/null || true
	ip link del vr 2>/dev/null || true
}
trap cleanup EXIT
cleanup

ip netns add "$NS_R"
ip netns add "$NS_C"

ip link add vc type veth peer name vr
ip link set vc netns "$NS_C"
ip link set vr netns "$NS_R"

ip -n "$NS_C" addr add 10.0.0.2/24 dev vc
ip -n "$NS_C" link set vc up
ip -n "$NS_C" link set lo up
ip -n "$NS_C" route add default via 10.0.0.1

ip -n "$NS_R" addr add 10.0.0.1/24 dev vr
ip -n "$NS_R" link set vr up
ip -n "$NS_R" link set lo up
# dummy "внешний" сегмент: 198.51.100.0/24 directly-connected -> роутер пытается ФОРВАРДИТЬ туда.
ip -n "$NS_R" link add dum0 type dummy
ip -n "$NS_R" addr add 198.51.100.254/24 dev dum0
ip -n "$NS_R" link set dum0 up
ip netns exec "$NS_R" sysctl -wq net.ipv4.ip_forward=1
ip netns exec "$NS_R" sysctl -wq net.ipv4.conf.all.rp_filter=0

# forward-chain drop counter (внешний LAN->non-private)
ks_drops() {
	ip netns exec "$NS_R" nft list chain inet monkey_business forward 2>/dev/null \
		| grep -oE 'counter packets [0-9]+' | grep -oE '[0-9]+$' | head -1
}
has_forward_hook() {
	ip netns exec "$NS_R" nft list table inet monkey_business 2>/dev/null | grep -q 'hook forward'
}
simulate_tproxy_miss() {
	# убрать prerouting-redirect -> пакет доходит до forward (как если бы Xray не перехватил)
	ip netns exec "$NS_R" nft flush chain inet monkey_business prerouting
}

# ---- kill_switch=1: утечка дропается ----
ip netns exec "$NS_R" env \
	MB_LAN_IFACE=vr MB_KILL_SWITCH=1 MB_NFT_COUNTER=counter \
	sh scripts/firewall/apply.sh >/dev/null

has_forward_hook || { echo "  FAIL: forward leak-guard chain missing with kill_switch=1"; exit 1; }
simulate_tproxy_miss

before=$(ks_drops); before="${before:-0}"
ip netns exec "$NS_C" nc -w1 "$EXT" 80 >/dev/null 2>&1 || true
after=$(ks_drops); after="${after:-0}"
echo "  [kill=1] forward drops: $before -> $after (want increase)"
[ "$after" -gt "$before" ] || { echo "  FAIL: leak not dropped with kill_switch=1"; exit 1; }

# приватный/локальный форвард не трогаем (accept-правила выше drop) — проверяем структурно
ip netns exec "$NS_R" nft list chain inet monkey_business forward | grep -q "ip daddr.*10.0.0.0/8.*accept" \
	|| { echo "  FAIL: private accept rule missing"; exit 1; }
echo "  [kill=1] private/local accept rule present"

# ---- kill_switch=0: fail-open, цепочки нет ----
ip netns exec "$NS_R" sh scripts/firewall/flush.sh >/dev/null
ip netns exec "$NS_R" env \
	MB_LAN_IFACE=vr MB_KILL_SWITCH=0 MB_NFT_COUNTER=counter \
	sh scripts/firewall/apply.sh >/dev/null

if has_forward_hook; then
	echo "  FAIL: forward leak-guard present with kill_switch=0 (should be fail-open)"
	exit 1
fi
echo "  [kill=0] no forward leak-guard (fail-open)"

echo "kill-switch leak-guard: OK"
