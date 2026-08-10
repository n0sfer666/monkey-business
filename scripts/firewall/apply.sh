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
FORCE="${MB_FORCE_PROXY:-}"

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

# force-proxy (MB_FORCE_PROXY): сырой пользовательский список «через туннель» (UCI custom_proxy).
# Явный выбор пользователя обязан быть сильнее ядерного geo-обхода: RU-адрес в списке иначе
# возвращается правилом @mb_ru4 return, до Xray не доходит вовсе, и правило в xray.json оказывается
# мёртвым — снаружи это «список не применился». Отсюда два инварианта: tproxy для этих адресов стоит
# ВЫШЕ bypass-return, а forward — дропает их РАНЬШЕ bypass-accept, иначе при упавшем Xray tproxy не
# находит сокет, пакет доезжает до forward и уходит наружу через @mb_ru4 accept: fail-open ровно для
# адреса, помеченного «только через туннель» (для не-RU адреса там сработал бы drop).
#
# Разбор и валидация — ЗДЕСЬ, а не у вызывающего: apply.sh единственный потребитель списка и
# единственное место, где известно, что примет nft; вторая копия правил разъехалась бы с этой.
# Разделители те же, что у classifyList() в src/generator/routing.uc (иначе firewall и xray.json
# разошлись бы на одной и той же строке): запятая и перевод строки, запись тримится, `#` —
# комментарий. Домены, geosite:/geoip: и битый ввод отсеиваются: nft-сет принимает только адреса,
# остальное разбирает Xray. Проверка строгая (октеты 0-255, префикс 0-32/0-128) — `999.999.999.999`
# и `1.2.3.4/33` проходят «похоже на адрес», но отклоняются уже ядром.
# `tproxy ip/ip6 to` — семейство обязано быть явным: в inet-таблице рядом с `ip daddr` голое
# `tproxy to` даёт «conflicting protocols specified: ip vs. unknown», и документ не применяется
# ЦЕЛИКОМ (проверено на железе) — т.е. молча остаётся прежний firewall без force-правил.
FORCE_OCT='(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])'
FORCE_RE="^$FORCE_OCT(\.$FORCE_OCT){3}(/(3[0-2]|[12]?[0-9]))?\$|^[0-9A-Fa-f:]*:[0-9A-Fa-f:]*(/(12[0-8]|1[01][0-9]|[1-9]?[0-9]))?\$"

F4=""
F6=""
while IFS= read -r entry; do
	case "$entry" in
		*:*) F6="$F6${F6:+ }$entry" ;;
		*) F4="$F4${F4:+ }$entry" ;;
	esac
done <<EOF
$(echo "$FORCE" | tr ',' '\n' | tr -d ' \t\r' | grep -E "$FORCE_RE")
EOF

FORCE_SETS=""
FORCE_PRE=""
FORCE_FWD=""
if [ "$BYPASS" = 1 ]; then
	if [ -n "$F4" ]; then
		FORCE_SETS="$FORCE_SETS
	set mb_force4 { type ipv4_addr; flags interval; auto-merge; }"
		FORCE_PRE="$FORCE_PRE
		iifname \"$LAN\" meta l4proto { tcp, udp } ip daddr @mb_force4 $COUNTER tproxy ip to :$PORT meta mark set $MARK"
		FORCE_FWD="$FORCE_FWD
		iifname \"$LAN\" ip daddr @mb_force4 $COUNTER drop"
	fi
	if [ -n "$F6" ]; then
		FORCE_SETS="$FORCE_SETS
	set mb_force6 { type ipv6_addr; flags interval; auto-merge; }"
		FORCE_PRE="$FORCE_PRE
		iifname \"$LAN\" meta l4proto { tcp, udp } ip6 daddr @mb_force6 $COUNTER tproxy ip6 to :$PORT meta mark set $MARK"
		FORCE_FWD="$FORCE_FWD
		iifname \"$LAN\" ip6 daddr @mb_force6 $COUNTER drop"
	fi
fi

# Kill-switch leak-guard собирается в forward-цепочку только при MB_KILL_SWITCH=1.
FORWARD=""
if [ "$KILL" = 1 ]; then
	FORWARD="
	chain forward {
		type filter hook forward priority filter; policy accept;
		iifname \"$LAN\" ip daddr $V4_LOCAL accept
		iifname \"$LAN\" ip6 daddr $V6_LOCAL accept$FORCE_FWD$BYPASS_FWD
		iifname \"$LAN\" $COUNTER drop
	}"
fi

# Сначала nft (set -e прервёт при сбое ДО policy-routing -> нет окна утечки с ip-rule без nft).
# Своп таблицы ОДНОЙ транзакцией: отдельный `nft delete table` перед созданием открывал окно, в
# котором нет ни kill-switch, ни tproxy — форвард LAN->WAN уходил открытым через fw4 (на каждом
# reload, т.е. и на каждом тике watchdog'а). Идиома: add (idempotent, delete требует существования)
# -> delete -> create; nft применяет файл целиком либо не применяет вовсе.
# `th dport 53 return` стоит выше bypass/force-правил намеренно: обе прежние ветки для :53 всё равно
# заканчивались return, так что порядок между ними ничего не менял, — зато теперь force не может
# утащить DNS в tproxy. Клиентский :53 обязан идти в dns_dnat -> Xray dns-инбаунд (raw-UDP-53 через
# прокси не ходит), и это верно независимо от того, что пользователь вписал в список.
nft -f - <<EOF
table inet monkey_business
delete table inet monkey_business
table inet monkey_business {$BYPASS_SETS$FORCE_SETS
	chain prerouting {
		type filter hook prerouting priority mangle; policy accept;
		ip daddr $V4_LOCAL return
		ip6 daddr $V6_LOCAL return
		iifname "$LAN" meta l4proto { tcp, udp } th dport 53 return$FORCE_PRE$BYPASS_PRE
		iifname "$LAN" meta l4proto { tcp, udp } $COUNTER tproxy to :$PORT meta mark set $MARK
	}
	chain dns_dnat {
		type nat hook prerouting priority -105; policy accept;
		iifname "$LAN" meta l4proto { tcp, udp } th dport 53 $COUNTER redirect to :$DNS_PORT
	}$FORWARD
}
EOF

# Элементы force-сетов — отдельной транзакцией, по той же причине, что и RU-сеты ниже: запись, которую
# не примет nft, не должна ронять документ с kill-switch. Загружаем ПООДИНОЧКЕ и ДО RU-сетов.
# Поодиночке — потому что одна транзакция на весь список означала бы «одна опечатка пользователя
# отменяет фикс для всех соседних адресов», причём молча; теперь битая запись теряет только себя и
# попадает в лог. До RU-сетов — потому что между двумя загрузками есть окно, где mb_ru4 уже полон, а
# mb_force4 ещё пуст: пакет к форсированному RU-адресу в этот момент ушёл бы напрямую, а
# установившееся в окне TCP-соединение осталось бы direct на весь свой срок.
FORCE_OK=""
if [ "$BYPASS" = 1 ]; then
	for e in $F4 $F6; do
		case "$e" in
			*:*) s=mb_force6 ;;
			*) s=mb_force4 ;;
		esac
		if err="$(nft add element inet monkey_business "$s" "{ $e }" 2>&1)"; then
			FORCE_OK="$FORCE_OK${FORCE_OK:+ }$e"
		else
			echo "force-proxy: nft rejected $e: $err"
		fi
	done
fi

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

# force=[…] перечисляет РЕАЛЬНО принятые ядром адреса, а не разобранные из списка: при bypass=0
# force-сетов нет вовсе, а отклонённая запись выше уже отдельной строкой в логе. Иначе строка
# рапортовала бы «применено» в обоих отказных сценариях — а лог здесь первое, куда смотрят, потому
# что снаружи баг выглядит как «список не применился».
echo "tproxy firewall applied (port=$PORT mark=$MARK lan=$LAN kill_switch=$KILL bypass=$BYPASS force=[$FORCE_OK] dns=>:$DNS_PORT)"
