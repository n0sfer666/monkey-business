#!/bin/sh
# Интеграция: прозрачный DNS. LAN-клиент шлёт DNS-запрос на роутер -> боевой firewall редиректит
# :53 на DNS-инбаунд Xray (:5300) -> dns-out -> dns-модуль (hosts) -> детерминированный ответ.
# Это проверяет фикс бага «клиентский DNS умирает под TPROXY». Offline: ответ из dns.hosts, без сети.
# Топология: client(mbc_dns) --veth-- router(mbr_dns); на router живой xray + apply.sh.
set -u

NS_R=mbr_dns
NS_C=mbc_dns
DNS_PORT=5300
XRAY_PID=""

cleanup() {
	[ -n "$XRAY_PID" ] && kill "$XRAY_PID" 2>/dev/null || true
	ip netns del "$NS_R" 2>/dev/null || true
	ip netns del "$NS_C" 2>/dev/null || true
	ip link del vrd 2>/dev/null || true
}
trap cleanup EXIT
cleanup

PUB=$(xray x25519 | grep -i 'public' | awk '{print $NF}')
[ -n "$PUB" ] || { echo "FAIL: no x25519 pubkey"; exit 1; }

# Конфиг через РЕАЛЬНЫЙ генератор (dns_transparent=true). Для живого запуска убираем tproxy-in
# (его тестирует tproxy.sh) и добавляем dns.hosts для детерминированного offline-резолва.
cat > /tmp/gen-dns.uc <<UEOF
import { generate } from "/w/src/generator/xray.uc";
import { writefile } from "fs";
let server = {
	tag: "t", protocol: "vless", address: "example.com", port: 443,
	uuid: "11111111-2222-3333-4444-555555555555", encryption: "none", flow: "",
	security: "reality", sni: "www.microsoft.com", fingerprint: "chrome", alpn: [],
	reality: { publicKey: "$PUB", shortId: "0123abcd", spiderX: "/" },
	transport: { type: "xhttp", path: "/x", host: "", mode: "auto", serviceName: "" },
	source: "manual"
};
let cfg = {
	global: { tproxy_port: 12345, routing_mode: "bypass-local", local_region: "ru" },
	server: server,
	anti_dpi: {},
	dns: { mode: "split", direct_dns: "127.0.0.1", doh_url: "https://1.1.1.1/dns-query" },
	dns_transparent: true
};
let out = generate(cfg);
let ib = [];
for (let x in out.inbounds) if (x.tag != "tproxy-in") push(ib, x);
out.inbounds = ib;
out.dns.hosts = { "test.mb": "203.0.113.45" };
writefile("/tmp/xray-dns.json", sprintf("%J", out));
UEOF
ucode /tmp/gen-dns.uc || { echo "FAIL: dns config generation"; exit 1; }

ip netns add "$NS_R"
ip netns add "$NS_C"
ip link add vcd type veth peer name vrd
ip link set vcd netns "$NS_C"
ip link set vrd netns "$NS_R"

ip -n "$NS_C" addr add 10.0.0.2/24 dev vcd
ip -n "$NS_C" link set vcd up
ip -n "$NS_C" link set lo up
ip -n "$NS_C" route add default via 10.0.0.1

ip -n "$NS_R" addr add 10.0.0.1/24 dev vrd
ip -n "$NS_R" link set vrd up
ip -n "$NS_R" link set lo up
ip netns exec "$NS_R" sysctl -wq net.ipv4.ip_forward=1
ip netns exec "$NS_R" sysctl -wq net.ipv4.conf.all.route_localnet=1

# Живой xray в router-netns (dns-in + dns-out; tproxy-in убран выше).
ip netns exec "$NS_R" env XRAY_LOCATION_ASSET=/usr/share/xray xray run -c /tmp/xray-dns.json >/tmp/xray-dns.log 2>&1 &
XRAY_PID=$!
sleep 2
kill -0 "$XRAY_PID" 2>/dev/null || { echo "FAIL: xray did not start"; cat /tmp/xray-dns.log; exit 1; }

# Боевой firewall: редирект клиентского :53 -> :$DNS_PORT (kill-switch off — для DNS не важен).
ip netns exec "$NS_R" env \
	MB_LAN_IFACE=vrd MB_DNS_PORT="$DNS_PORT" MB_KILL_SWITCH=0 MB_NFT_COUNTER=counter \
	sh scripts/firewall/apply.sh >/dev/null

# Клиент резолвит test.mb через роутер по обычному UDP 53 (раньше это таймаутило).
out=$(ip netns exec "$NS_C" nslookup test.mb 10.0.0.1 2>&1)
if ! echo "$out" | grep -q "203.0.113.45"; then
	echo "FAIL: client could not resolve via transparent DNS"
	echo "$out"; echo "--- xray log ---"; cat /tmp/xray-dns.log
	exit 1
fi
echo "  [client] test.mb -> 203.0.113.45 via transparent DNS: OK"

# Правило редиректа реально сработало.
pkts=$(ip netns exec "$NS_R" nft list chain inet monkey_business dns_dnat 2>/dev/null \
	| grep -oE 'counter packets [0-9]+' | grep -oE '[0-9]+$' | head -1)
[ "${pkts:-0}" -gt 0 ] || { echo "  FAIL: dns redirect rule not hit (counter=0)"; exit 1; }
echo "  [firewall] dns redirect counter=$pkts"

echo "transparent DNS: OK"
