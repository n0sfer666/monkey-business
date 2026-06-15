#!/bin/sh
# TPROXY transparent-proxy firewall (nftables) + policy routing + kill-switch.
# Перехватывает TCP+UDP от LAN-клиентов в локальный tproxy-порт Xray.
# Приватные/локальные сети не перехватываются (direct).
#
# Kill-switch (fail-closed): прокси-трафик терминируется TPROXY в prerouting (уходит локально в
# Xray). Значит ЛЮБОЙ форвардимый LAN->non-private пакет = утечка мимо туннеля (Xray упал, дыра в
# правилах, не-TCP/UDP вроде ICMP). MB_KILL_SWITCH=1 дропает его в forward-хуке; =0 — fail-open
# (direct-фолбэк). Локальный direct идёт через Xray (OUTPUT), не LAN-forward, поэтому split не ломается.
#
# Параметры через окружение (дефолты — боевые):
#   MB_TPROXY_PORT (12345) MB_FWMARK (1) MB_RT_TABLE (100) MB_DNS_PORT (5300)
#   MB_LAN_IFACE (br-lan)  MB_KILL_SWITCH (1)  MB_NFT_COUNTER ("" | "counter" для тестов)
#
# DNS: клиентский :53 НЕ уходит под общий TPROXY (raw-UDP-53 через прокси не ходит), а редиректится
# на локальный DNS-инбаунд Xray (MB_DNS_PORT), где dns-модуль применяет сплит. Иначе DNS клиентов мёртв.
set -eu

PORT="${MB_TPROXY_PORT:-12345}"
MARK="${MB_FWMARK:-1}"
TABLE="${MB_RT_TABLE:-100}"
LAN="${MB_LAN_IFACE:-br-lan}"
KILL="${MB_KILL_SWITCH:-1}"
DNS_PORT="${MB_DNS_PORT:-5300}"
COUNTER="${MB_NFT_COUNTER:-}"

V4_LOCAL="{ 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10, 224.0.0.0/4, 240.0.0.0/4 }"
V6_LOCAL="{ ::1, fc00::/7, fe80::/10 }"

# Kill-switch leak-guard собирается в forward-цепочку только при MB_KILL_SWITCH=1.
FORWARD=""
if [ "$KILL" = 1 ]; then
	FORWARD="
	chain forward {
		type filter hook forward priority filter; policy accept;
		iifname \"$LAN\" ip daddr $V4_LOCAL accept
		iifname \"$LAN\" ip6 daddr $V6_LOCAL accept
		iifname \"$LAN\" $COUNTER drop
	}"
fi

# идемпотентность: убрать прежнюю таблицу (set -e -> guard) перед пересозданием
nft delete table inet monkey_business 2>/dev/null || true

# Сначала nft (set -e прервёт при сбое ДО policy-routing -> нет окна утечки с ip-rule без nft).
nft -f - <<EOF
table inet monkey_business {
	chain prerouting {
		type filter hook prerouting priority mangle; policy accept;
		ip daddr $V4_LOCAL return
		ip6 daddr $V6_LOCAL return
		iifname "$LAN" meta l4proto { tcp, udp } th dport 53 return
		iifname "$LAN" meta l4proto { tcp, udp } $COUNTER tproxy to :$PORT meta mark set $MARK
	}
	chain dns_dnat {
		type nat hook prerouting priority -105; policy accept;
		iifname "$LAN" meta l4proto { tcp, udp } th dport 53 $COUNTER redirect to :$DNS_PORT
	}$FORWARD
}
EOF

ip rule add fwmark "$MARK" lookup "$TABLE" 2>/dev/null || true
ip route add local 0.0.0.0/0 dev lo table "$TABLE" 2>/dev/null || true

echo "tproxy firewall applied (port=$PORT mark=$MARK lan=$LAN kill_switch=$KILL dns=>:$DNS_PORT)"
