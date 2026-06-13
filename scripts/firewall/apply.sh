#!/bin/sh
# TPROXY transparent-proxy firewall (nftables) + policy routing.
# Перехватывает TCP+UDP от LAN-клиентов в локальный tproxy-порт Xray.
# Приватные/локальные сети не перехватываются (direct).
#
# Параметры через окружение (дефолты — боевые):
#   MB_TPROXY_PORT (12345) MB_FWMARK (1) MB_RT_TABLE (100)
#   MB_LAN_IFACE (br-lan)  MB_NFT_COUNTER ("" | "counter" для тестов)
set -eu

PORT="${MB_TPROXY_PORT:-12345}"
MARK="${MB_FWMARK:-1}"
TABLE="${MB_RT_TABLE:-100}"
LAN="${MB_LAN_IFACE:-br-lan}"
COUNTER="${MB_NFT_COUNTER:-}"

# Сначала nft (set -e прервёт при сбое ДО policy-routing -> нет окна утечки с ip-rule без nft).
nft -f - <<EOF
table inet monkey_business {
	chain prerouting {
		type filter hook prerouting priority mangle; policy accept;
		ip daddr { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10, 224.0.0.0/4, 240.0.0.0/4 } return
		ip6 daddr { ::1, fc00::/7, fe80::/10 } return
		iifname "$LAN" meta l4proto { tcp, udp } $COUNTER tproxy to :$PORT meta mark set $MARK
	}
}
EOF

ip rule add fwmark "$MARK" lookup "$TABLE" 2>/dev/null || true
ip route add local 0.0.0.0/0 dev lo table "$TABLE" 2>/dev/null || true

echo "tproxy firewall applied (port=$PORT mark=$MARK lan=$LAN)"
