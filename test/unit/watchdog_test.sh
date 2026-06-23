#!/bin/sh
# Юнит-тест машины состояний watchdog (root/usr/share/monkey-business/watchdog.sh).
# Сорсит скрипт с MB_WD_SOURCED=1 (main не запускается) и подменяет все побочные эффекты
# (uci/pidof/curl/init.d/date) мок-функциями. Сетевые пробы (live/vpn/direct) и vpn_reconnect
# замоканы. Проверяет переходы HEALTHY<->RECONNECTING<->DOWN, reconnect-first, leak, net/vpn,
# лог только на переходах. Сеть/root не нужны — годен для make test-unit.
# MB_WD_EXIT_EVERY=1 — exit-сверка каждый tick (детерминизм); периодичность тестим отдельно.
# Переменные ниже используются сорснутым watchdog.sh — SC2034/SC1090 ложны.
# shellcheck disable=SC2034,SC1090
set -u

SELF_DIR=$(dirname "$0")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

MB_WD_SOURCED=1
MB_WD_EXIT_EVERY=1
MB_WD_LIB="$SELF_DIR/../../root/usr/share/monkey-business"
# shellcheck source=/dev/null
. "$SELF_DIR/../../root/usr/share/monkey-business/watchdog.sh"

STATE_DIR="$T"; STATE="$T/state"; LOCK="$T/lock"

HOME_IP='9.9.9.9'         # домашний (direct) IP
EXIT1='1.2.3.4'           # exit через VPN (отличается от home → healthy)
EXIT2='3.3.3.3'           # exit после смены сервера

sleep() { :; }
read_intent() { cat "$T/intent" 2>/dev/null || echo 0; }
selected_tag() { cat "$T/tag" 2>/dev/null || echo ''; }
vpn_running() { [ -f "$T/running" ]; }
vpn_start() { : > "$T/running"; echo start >> "$T/actions"; }
vpn_stop() { rm -f "$T/running"; echo stop >> "$T/actions"; }
vpn_reconnect() { echo reconnect >> "$T/actions"; }
live_probe() { [ -f "$T/live" ]; }            # файл = liveness ok
vpn_probe() { _pop "$T/vpn_q"; }              # exit-IP из очереди (пусто = провал пробы)
direct_probe() { cat "$T/direct" 2>/dev/null || echo ''; }
log_event() { echo "$1" >> "$T/log"; }

_pop() { head -n1 "$1" 2>/dev/null; tail -n +2 "$1" > "$1.t" 2>/dev/null; mv "$1.t" "$1" 2>/dev/null; }
enq() { printf '%s\n' "$1" >> "$T/vpn_q"; }
runtick() { MB_WD_NOW="$1"; tick; }
sval() { ( . "$STATE" 2>/dev/null; eval "echo \$$1" ); }

reset() {
	rm -rf "$T"; mkdir -p "$T"
	echo 1 > "$T/intent"
	echo 'Estonia Tallinn-1' > "$T/tag"
	echo "$HOME_IP" > "$T/direct"
	: > "$T/running"
	: > "$T/live"
}
seed_down() {
	kind="$1"
	ts=$(sig "$(cat "$T/tag")")
	{ echo "WD_PHASE=down"; echo "WD_FAILS=0"; echo "WD_BASE_IP=$EXIT1"; echo "WD_HOME_IP=$HOME_IP"
	  echo "WD_TAGSIG=$ts"; echo "WD_NEXT=0"; echo "WD_DOWNKIND=$kind"; } > "$STATE"
}
seed_reconnecting() {
	ts=$(sig "$(cat "$T/tag")")
	{ echo "WD_PHASE=reconnecting"; echo "WD_FAILS=0"; echo "WD_BASE_IP=$EXIT1"; echo "WD_HOME_IP=$HOME_IP"
	  echo "WD_TAGSIG=$ts"; echo "WD_NEXT=0"; echo "WD_DOWNKIND=vpn"; echo "WD_RECTRIES=0"; } > "$STATE"
}

PASS=0; FAIL=0
eq() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL $1: want[$3] got[$2]"; fi; }
has() { if grep -q "$3" "$2" 2>/dev/null; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL $1: '$3' missing in $2"; fi; }
no() { if grep -q "$3" "$2" 2>/dev/null; then FAIL=$((FAIL+1)); echo "FAIL $1: '$3' unexpected in $2"; else PASS=$((PASS+1)); fi; }

# 1. baseline-захват: первый здоровый ответ фиксирует exit EXIT1 и home, без лога.
reset; enq "$EXIT1"; runtick 1000
eq "baseline.phase" "$(sval WD_PHASE)" healthy
eq "baseline.exit" "$(sval WD_BASE_IP)" "$EXIT1"
eq "baseline.home" "$(sval WD_HOME_IP)" "$HOME_IP"
eq "baseline.fails" "$(sval WD_FAILS)" 0
eq "baseline.nolog" "$([ -f "$T/log" ] && echo y || echo n)" n

# 2. до лимита не падаем: 2 провала liveness -> ещё healthy.
reset; enq "$EXIT1"; runtick 1000; rm -f "$T/live"
n=1; while [ "$n" -le 2 ]; do runtick $((1000 + n*60)); n=$((n+1)); done
eq "under.phase" "$(sval WD_PHASE)" healthy
eq "under.fails" "$(sval WD_FAILS)" 2

# 3. 3 провала liveness подряд при живом direct -> RECONNECTING (НЕ сразу на direct), лог, без stop.
reset; enq "$EXIT1"; runtick 1000; rm -f "$T/live"
n=1; while [ "$n" -le 3 ]; do runtick $((1000 + n*60)); n=$((n+1)); done
eq "degrade.phase" "$(sval WD_PHASE)" reconnecting
eq "degrade.kind" "$(sval WD_DOWNKIND)" vpn
has "degrade.log" "$T/log" "Reconnecting"
no "degrade.nostop" "$T/actions" stop

# 4. RECONNECTING + reconnect помог (live вернулся + exit) -> HEALTHY, reconnect в actions, без stop.
reset; seed_reconnecting; : > "$T/live"; enq "$EXIT1"
runtick 5000
eq "recover.phase" "$(sval WD_PHASE)" healthy
has "recover.reconnect" "$T/actions" reconnect
no "recover.nostop" "$T/actions" stop
has "recover.log" "$T/log" "VPN reconnected"

# 5. RECONNECTING + reconnect не помогает RECONNECT_LIMIT(2) раз -> DOWN(vpn), stop, лог failover.
reset; seed_reconnecting; rm -f "$T/live"
runtick 5000                                  # попытка 1: rectries 0->1, ещё reconnecting
eq "failover.mid" "$(sval WD_PHASE)" reconnecting
runtick 5100                                  # попытка 2: rectries ->2 == limit -> down(vpn)
eq "failover.phase" "$(sval WD_PHASE)" down
eq "failover.kind" "$(sval WD_DOWNKIND)" vpn
has "failover.stop" "$T/actions" stop
has "failover.log" "$T/log" "Reconnect failed"

# 6. HEALTHY: 3 провала + direct мёртв -> DOWN(net) напрямую, без reconnect.
reset; enq "$EXIT1"; runtick 1000; rm -f "$T/live"; : > "$T/direct"
n=1; while [ "$n" -le 3 ]; do runtick $((1000 + n*60)); n=$((n+1)); done
eq "netdown.phase" "$(sval WD_PHASE)" down
eq "netdown.kind" "$(sval WD_DOWNKIND)" net
has "netdown.stop" "$T/actions" stop
no "netdown.noreconnect" "$T/actions" reconnect

# 7. RECONNECTING + сеть легла (direct пусто) -> DOWN(net), без зацикливания.
reset; seed_reconnecting; rm -f "$T/live"; : > "$T/direct"
runtick 5000
eq "netdrop.phase" "$(sval WD_PHASE)" down
eq "netdrop.kind" "$(sval WD_DOWNKIND)" net
has "netdrop.log" "$T/log" "Network down during reconnect"

# 8. DOWN + сеть полностью легла (direct пусто): без старта VPN, лог "fully down", kind->net.
reset; seed_down vpn; : > "$T/direct"; rm -f "$T/running"
runtick 5000
eq "fulldown.phase" "$(sval WD_PHASE)" down
eq "fulldown.kind" "$(sval WD_DOWNKIND)" net
eq "fulldown.noaction" "$([ -f "$T/actions" ] && echo y || echo n)" n
has "fulldown.log" "$T/log" "fully down"

# 9. DOWN(net) -> сеть ожила + VPN поднялся: лог recovered+restored, phase healthy.
reset; seed_down net; rm -f "$T/running"; enq "$EXIT1"
runtick 6000
eq "recovervpn.phase" "$(sval WD_PHASE)" healthy
has "recovervpn.start" "$T/actions" start
has "recovervpn.log1" "$T/log" "Network recovered"
has "recovervpn.log2" "$T/log" "VPN restored"

# 10. DOWN(net) -> сеть ожила, но VPN всё ещё дохлый: стоп VPN, лог staying direct, DOWN(vpn).
reset; seed_down net; rm -f "$T/running"; rm -f "$T/live"
runtick 7000
eq "stilldown.phase" "$(sval WD_PHASE)" down
eq "stilldown.kind" "$(sval WD_DOWNKIND)" vpn
has "stilldown.stop" "$T/actions" stop
has "stilldown.staydirect" "$T/log" "Staying on direct"

# 11. leak на exit-сверке: liveness ok, exit==home -> провал. С EXIT_EVERY=3: первые 2 цикла
#     не сверяют exit (healthy), 3-й сверяет и ловит leak (fails->1).
reset; EXIT_EVERY=3
enq "$HOME_IP"
runtick 1000; eq "leak.t1" "$(sval WD_FAILS)" 0
runtick 1060; eq "leak.t2" "$(sval WD_FAILS)" 0
runtick 1120; eq "leak.t3" "$(sval WD_FAILS)" 1
eq "leak.phase" "$(sval WD_PHASE)" healthy
EXIT_EVERY=1

# 12. intent=0 -> watchdog idle, state удаляется.
reset; echo 0 > "$T/intent"; : > "$STATE"
runtick 8000
eq "idle.state_removed" "$([ -f "$STATE" ] && echo y || echo n)" n

# 13. смена сервера (tag) -> сброс exit-baseline, новый exit фиксируется.
reset; enq "$EXIT1"; runtick 1000
echo 'Netherlands Amsterdam-2' > "$T/tag"; enq "$EXIT2"; runtick 1060
eq "tagchange.exit" "$(sval WD_BASE_IP)" "$EXIT2"
eq "tagchange.phase" "$(sval WD_PHASE)" healthy

printf '\nwatchdog_test: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
