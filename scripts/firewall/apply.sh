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
BYPASS="${MB_DIRECT_BYPASS:-1}"
RUSET_DIR="${MB_RUSET_DIR:-/usr/share/monkey-business}"

V4_LOCAL="{ 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10, 224.0.0.0/4, 240.0.0.0/4 }"
V6_LOCAL="{ ::1, fc00::/7, fe80::/10 }"

# direct-bypass (MB_DIRECT_BYPASS=1): RU-CIDR минует Xray, маршрутизируется ядром нативно.
# Сеты mb_ru4/mb_ru6 объявляются в таблице, элементы подгружаются из ru4.nft/ru6.nft после создания.
# prerouting: @mb_ru4/6 -> return (не в tproxy). forward: @mb_ru4/6 -> accept (kill-switch не дропает RU).
BYPASS_SETS=""
BYPASS_PRE=""
BYPASS_FWD=""
if [ "$BYPASS" = 1 ]; then
	BYPASS_SETS="
	set mb_ru4 { type ipv4_addr; flags interval; auto-merge; }
	set mb_ru6 { type ipv6_addr; flags interval; auto-merge; }"
	BYPASS_PRE="
		iifname \"$LAN\" ip daddr @mb_ru4 return
		iifname \"$LAN\" ip6 daddr @mb_ru6 return"
	BYPASS_FWD="
		iifname \"$LAN\" ip daddr @mb_ru4 accept
		iifname \"$LAN\" ip6 daddr @mb_ru6 accept"
fi

# Kill-switch leak-guard собирается в forward-цепочку только при MB_KILL_SWITCH=1.
FORWARD=""
if [ "$KILL" = 1 ]; then
	FORWARD="
	chain forward {
		type filter hook forward priority filter; policy accept;
		iifname \"$LAN\" ip daddr $V4_LOCAL accept
		iifname \"$LAN\" ip6 daddr $V6_LOCAL accept$BYPASS_FWD
		iifname \"$LAN\" $COUNTER drop
	}"
fi

# Сначала nft (set -e прервёт при сбое ДО policy-routing -> нет окна утечки с ip-rule без nft).
# Своп таблицы ОДНОЙ транзакцией: отдельный `nft delete table` перед созданием открывал окно, в
# котором нет ни kill-switch, ни tproxy — форвард LAN->WAN уходил открытым через fw4 (на каждом
# reload, т.е. и на каждом тике watchdog'а). Идиома: add (idempotent, delete требует существования)
# -> delete -> create; nft применяет файл целиком либо не применяет вовсе.
nft -f - <<EOF
table inet monkey_business
delete table inet monkey_business
table inet monkey_business {$BYPASS_SETS
	chain prerouting {
		type filter hook prerouting priority mangle; policy accept;
		ip daddr $V4_LOCAL return
		ip6 daddr $V6_LOCAL return$BYPASS_PRE
		iifname "$LAN" meta l4proto { tcp, udp } th dport 53 return
		iifname "$LAN" meta l4proto { tcp, udp } $COUNTER tproxy to :$PORT meta mark set $MARK
	}
	chain dns_dnat {
		type nat hook prerouting priority -105; policy accept;
		iifname "$LAN" meta l4proto { tcp, udp } th dport 53 $COUNTER redirect to :$DNS_PORT
	}$FORWARD
}
EOF

# direct-bypass: подгрузить элементы RU-сетов в уже созданную таблицу (guarded, не фатально).
# Намеренно ОТДЕЛЬНЫМИ транзакциями, а не внутри документа выше: битый/обрезанный ru4.nft уронил бы
# весь документ, а на загрузке (прежней таблицы нет) это firewall без kill-switch. Худший случай
# здесь — пустой bypass: RU-трафик идёт через туннель, но правила на месте.
if [ "$BYPASS" = 1 ]; then
	[ -f "$RUSET_DIR/ru4.nft" ] && nft -f "$RUSET_DIR/ru4.nft" 2>/dev/null || true
	[ -f "$RUSET_DIR/ru6.nft" ] && nft -f "$RUSET_DIR/ru6.nft" 2>/dev/null || true
fi

# `ip rule add` дубликаты не проверяет, а apply.sh зовётся на каждом старте и каждом config_apply
# (watchdog делает это по нескольку раз за инцидент) — правила копились бы до flush.sh, который
# снимает ровно одно. Снимаем все свои и ставим одно: результат не зависит от числа прошлых вызовов.
# Потолок обязателен: цикл «пока удаляется» на стабе/реализации `ip`, всегда возвращающей 0,
# крутился бы вечно, а восемь снятий с запасом покрывают любое реальное накопление.
i=0
while [ "$i" -lt 8 ] && ip rule del fwmark "$MARK" lookup "$TABLE" 2>/dev/null; do i=$((i + 1)); done
ip rule add fwmark "$MARK" lookup "$TABLE" 2>/dev/null || true
ip route add local 0.0.0.0/0 dev lo table "$TABLE" 2>/dev/null || true

echo "tproxy firewall applied (port=$PORT mark=$MARK lan=$LAN kill_switch=$KILL bypass=$BYPASS dns=>:$DNS_PORT)"
