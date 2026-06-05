#!/bin/sh
# Интеграция: реальный firewall-артефакт (scripts/firewall/apply.sh) перехватывает
# форвардимый трафик LAN-клиента в TPROXY (prerouting), а локальный/приватный — нет.
# Топология: client(mbc) --veth-- router(mbr). На router применяется боевой ruleset.
set -u

NS_R=mbr
NS_C=mbc
PORT=12345

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
ip netns exec "$NS_R" sysctl -wq net.ipv4.ip_forward=1
ip netns exec "$NS_R" sysctl -wq net.ipv4.conf.all.route_localnet=1
ip netns exec "$NS_R" sysctl -wq net.ipv4.conf.all.rp_filter=0
ip netns exec "$NS_R" sysctl -wq net.ipv4.conf.vr.rp_filter=0

# Применяем БОЕВОЙ firewall-скрипт внутри router-netns (с counter для проверки).
ip netns exec "$NS_R" env \
	MB_LAN_IFACE=vr MB_TPROXY_PORT="$PORT" MB_NFT_COUNTER=counter \
	sh scripts/firewall/apply.sh

assert_counter() {
	desc="$1"
	want="$2"
	pkts=$(ip netns exec "$NS_R" nft list table inet monkey_business \
		| grep -oE 'counter packets [0-9]+' | grep -oE '[0-9]+$' | head -1)
	pkts="${pkts:-0}"
	echo "  [$desc] intercepted packets=$pkts (want $want)"
	if [ "$want" = "gt0" ]; then
		[ "$pkts" -gt 0 ] || { echo "  FAIL: expected interception"; return 1; }
	else
		[ "$pkts" = "0" ] || { echo "  FAIL: expected NO interception, got $pkts"; return 1; }
	fi
	return 0
}

# 1) Приватный TCP (к роутеру) НЕ перехватывается (срабатывает private-return).
ip netns exec "$NS_C" nc -w1 10.0.0.1 22 >/dev/null 2>&1 || true
assert_counter "private->no-intercept" "0" || exit 1

# 2) Внешний трафик (TEST-NET 198.51.100.1) перехватывается prerouting-правилом.
ip netns exec "$NS_C" nc -w1 198.51.100.1 80 >/dev/null 2>&1 || true
assert_counter "external->intercept" "gt0" || exit 1

# 3) ip rule fwmark -> table присутствует.
ip netns exec "$NS_R" ip rule show | grep -q "fwmark 0x1 lookup 100" \
	|| { echo "  FAIL: fwmark ip rule missing"; exit 1; }
echo "  [ip-rule] fwmark->table 100 present"

echo "tproxy interception: OK"
