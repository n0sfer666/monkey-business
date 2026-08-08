#!/bin/sh
# Юнит-тест машины состояний watchdog (root/usr/share/monkey-business/watchdog.sh).
# Сорсит скрипт с MB_WD_SOURCED=1 (main не запускается) и подменяет все побочные эффекты
# (uci/pidof/curl/init.d/date) мок-функциями. Замоканы сетевые пробы (live/vpn/direct), доступ к
# процессам (pid-файл, kill), init.d и ubus; сами ступени лестницы — боевые.
# Проверяет переходы HEALTHY<->RECONNECTING<->DOWN, лестницу восстановления
# (recovery.sh: soft -> hard -> failover -> full), leak, net/vpn, лог только на переходах.
# Сеть/root не нужны — годен для make test-unit.
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
# selected_tag НЕ мокаем: подставляем боевой функции свой файл, чтобы тесты гоняли реальный
# ридер, а не его копию (опечатка в пути иначе прошла бы зелёной).
ACTIVE="$T/tag"

HOME_IP='9.9.9.9'         # домашний (direct) IP
EXIT1='1.2.3.4'           # exit через VPN (отличается от home → healthy)
EXIT2='3.3.3.3'           # exit после смены сервера

sleep() { :; }
read_intent() { cat "$T/intent" 2>/dev/null || echo 0; }
vpn_running() { [ -f "$T/running" ]; }
vpn_start() { : > "$T/running"; echo 4242 > "$T/pids"; echo start >> "$T/actions"; }
# STOP_DELAY — сколько секунд «съедает» попытка: часы в тесте заморожены, и без него не отличить
# паузу, отсчитанную от конца попытки, от паузы от начала тика (см. 10h).
STOP_DELAY=0
vpn_stop() { rm -f "$T/running" "$T/pids"; echo stop >> "$T/actions"; MB_WD_NOW=$((MB_WD_NOW + STOP_DELAY)); }
# Все ступени лестницы (vpn_reconnect/vpn_hard_restart/failover_step/vpn_full_cycle и диспетчер
# recover_step) гоняем БОЕВЫЕ — их порядок и жёсткость и есть предмет теста. Замокан только доступ к
# процессам: pid-файл вместо таблицы процессов, запись вместо сигналов, плюс init.d (vpn_start/stop).
# $T/term_ignored — зависший xray, который не умирает от SIGTERM: жёсткая ступень обязана дождаться
# и дожать SIGKILL.
xray_pids() { p=$(cat "$T/pids" 2>/dev/null || echo ''); [ -n "$p" ] || return 1; echo "$p"; }
pidset() { cat "$T/pids" 2>/dev/null || echo ''; }
kill() {
	# -0 — не сигнал, а проверка «жив ли pid»: ни в actions, ни в побочные эффекты не попадает.
	[ "${1:-}" = -0 ] && { grep -qx "$2" "$T/pids" 2>/dev/null; return; }
	echo "kill $*" >> "$T/actions"
	case "${1:-}" in
		-9) rm -f "$T/pids" "$T/running" ;;
		*)  [ -f "$T/term_ignored" ] || rm -f "$T/pids" "$T/running" ;;
	esac
}
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
	echo 4242 > "$T/pids"
	: > "$T/live"
}
seed_down() {
	kind="$1"
	ts=$(sig "$(cat "$T/tag")")
	{ echo "WD_PHASE=down"; echo "WD_FAILS=0"; echo "WD_BASE_IP=$EXIT1"; echo "WD_HOME_IP=$HOME_IP"
	  echo "WD_TAGSIG=$ts"; echo "WD_NEXT=0"; echo "WD_DOWNKIND=$kind"; } > "$STATE"
}
# $1 — ступень лестницы, с которой начинается тик (по умолчанию первая, мягкая).
seed_reconnecting() {
	ts=$(sig "$(cat "$T/tag")")
	{ echo "WD_PHASE=reconnecting"; echo "WD_FAILS=0"; echo "WD_BASE_IP=$EXIT1"; echo "WD_HOME_IP=$HOME_IP"
	  echo "WD_TAGSIG=$ts"; echo "WD_NEXT=0"; echo "WD_DOWNKIND=vpn"; echo "WD_RECTRIES=${1:-0}"; } > "$STATE"
}

PASS=0; FAIL=0
eq() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL $1: want[$3] got[$2]"; fi; }
has() { if grep -q "$3" "$2" 2>/dev/null; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL $1: '$3' missing in $2"; fi; }
no() { if grep -q "$3" "$2" 2>/dev/null; then FAIL=$((FAIL+1)); echo "FAIL $1: '$3' unexpected in $2"; else PASS=$((PASS+1)); fi; }

# 0. Разбор ответа config_apply — БОЕВЫМ failover_switch (замокан только ubus). Идёт до подмены
#    failover_switch ниже: дальше он нужен машине состояний как управляемая ступень.
#    Ключевой случай — probed:false: конфиг применён и сервис перезапущен (ровно как ручной Turn on),
#    просто ни один кандидат не прошёл эфемерную пробу. Прежний код читал это как «переключиться не
#    удалось», пропускал health-проверку и ронял watchdog в down по живому туннелю.
ubus() { cat "$T/ubus_out" 2>/dev/null; return "$(cat "$T/ubus_rc" 2>/dev/null || echo 0)"; }
fo_case() { printf '%s' "$1" > "$T/ubus_out"; printf '%s' "${2:-0}" > "$T/ubus_rc"; failover_switch; }

fo_case '{ "ok": true, "server": "X", "probed": true }'; rc=$?
eq "parse.probed.rc" "$rc" 0
eq "parse.probed.flag" "$WD_PROBED" 1
fo_case '{ "ok": true, "server": "X", "probed": false }'; rc=$?
eq "parse.unprobed.rc" "$rc" 0
eq "parse.unprobed.flag" "$WD_PROBED" 0
fo_case '{ "error": "no servers" }'; rc=$?
eq "parse.error.rc" "$rc" 1
fo_case '{ "ok": true, "probed": true }' 1; rc=$?
eq "parse.ubusfail.rc" "$rc" 1

# failover: при наличии $T/failover_ok «переключает» на рабочий сервер (включает live + exit EXIT2).
# Тег меняется в ЛЮБОМ исходе — config_apply зовёт setSelected и на фолбэке servers[0] тоже.
# $T/fo_left — переданный watchdog'ом потолок ожидания ubus: его достаточность проверяет тест 16.
failover_switch() {
	echo 'France Paris-9' > "$T/tag"
	echo "${1:-0}" > "$T/fo_left"
	[ -f "$T/failover_ok" ] && { : > "$T/live"; enq "$EXIT2"; echo failover >> "$T/actions"; return 0; }
	return 1
}

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

# 4. RECONNECTING + мягкая ступень помогла (live вернулся + exit) -> HEALTHY, без stop.
#    Ступень называется в логе: по logread видно, чем именно починилось.
reset; seed_reconnecting; : > "$T/live"; enq "$EXIT1"
runtick 5000
eq "recover.phase" "$(sval WD_PHASE)" healthy
has "recover.bounce" "$T/actions" "kill 4242"
no "recover.nokill9" "$T/actions" "kill -9"
no "recover.nostop" "$T/actions" stop
has "recover.log" "$T/log" "recovered by soft bounce"

# 5. Лестница по одной ступени на тик: soft -> hard -> failover -> full, и только исчерпав ВСЕ
#    RECONNECT_LIMIT(4) — down(vpn). Раньше лестница кончалась на мягком bounce, бессильном против
#    зависшего xray и мёртвого сервера, и туннель поднимался только руками.
#    actions чистим перед каждым тиком: инвариант «ступени 0-2 kill-switch НЕ снимают» проверяется
#    поштучно, иначе один общий stop от последней ступени сделал бы его непроверяемым.
reset; seed_reconnecting; rm -f "$T/live"
runtick 5000
eq "ladder.step0.phase" "$(sval WD_PHASE)" reconnecting
has "ladder.step0.did" "$T/actions" "kill 4242"
no "ladder.step0.noleak" "$T/actions" stop
has "ladder.step0.next" "$T/log" "escalating to 'hard restart'"
: > "$T/actions"
runtick 5100                                  # жёсткая: SIGTERM -> смерть -> init.d start
has "ladder.step1.kill" "$T/actions" "kill 4242"
has "ladder.step1.start" "$T/actions" start
no "ladder.step1.noleak" "$T/actions" stop
has "ladder.step1.next" "$T/log" "escalating to 'failover'"
: > "$T/actions"
runtick 5200                                  # failover: config_apply не нашёл рабочего
no "ladder.step2.noleak" "$T/actions" stop
has "ladder.step2.log" "$T/log" "config_apply failed"
has "ladder.step2.next" "$T/log" "escalating to 'full stop/start'"
eq "ladder.step2.phase" "$(sval WD_PHASE)" reconnecting
runtick 5300                                  # полный цикл не помог -> down
eq "ladder.phase" "$(sval WD_PHASE)" down
eq "ladder.kind" "$(sval WD_DOWNKIND)" vpn
has "ladder.stop" "$T/actions" stop
has "ladder.log" "$T/log" "All 4 recovery steps failed"

# 5b. Ступень failover нашла рабочий сервер -> HEALTHY, до разрушительных ступеней не доходим.
reset; seed_reconnecting 2; rm -f "$T/live"; : > "$T/failover_ok"
runtick 5000
eq "foswitch.phase" "$(sval WD_PHASE)" healthy
has "foswitch.did" "$T/actions" failover
has "foswitch.log" "$T/log" "recovered by failover"

# 5c. РЕГРЕСС: xray, игнорирующий SIGTERM. Мягкая ступень на таком молча не делает ничего (процесс
#     жив = «поднялся»), поэтому жёсткая обязана дождаться и дожать SIGKILL, а поднимать через
#     init.d — заодно apply.sh пересобирает nft-таблицу и policy-routing.
reset; seed_reconnecting 1; : > "$T/term_ignored"; enq "$EXIT1"
runtick 5000
has "wedged.term" "$T/actions" "kill 4242"
has "wedged.sigkill" "$T/actions" "kill -9"
has "wedged.start" "$T/actions" start
eq "wedged.phase" "$(sval WD_PHASE)" healthy
has "wedged.log" "$T/log" "recovered by hard restart"

# 5d. Последняя ступень — полный аналог ручного Turn off/Turn on. Порядок критичен: перевыбор
#     сервера идёт ПЕРВЫМ, под поднятым kill-switch'ем, и лишь потом stop (flush.sh снимает
#     таблицу) -> start. Обратный порядок держал бы LAN открытой весь перебор кандидатов — до
#     UBUS_TIMEOUT, единственная утечка без потолка.
reset; seed_reconnecting 3; rm -f "$T/live"; : > "$T/failover_ok"
runtick 5000
eq "full.order" "$(tr '\n' ',' < "$T/actions")" "failover,stop,start,"
eq "full.phase" "$(sval WD_PHASE)" healthy
has "full.log" "$T/log" "recovered by full stop/start"

# 5e. Процесс исчез между проверкой «жив» и снимком pid'ов (procd, ручной Off): сигналить некому,
#     и ждать смерти тоже — иначе жёсткая ступень выспала бы весь KILL_WAIT из дефицитного тика.
reset; seed_reconnecting 1; rm -f "$T/pids"; enq "$EXIT1"
runtick 5000
no "gone.nokill" "$T/actions" kill
has "gone.start" "$T/actions" start
eq "gone.phase" "$(sval WD_PHASE)" healthy

# 6. HEALTHY: 3 провала + direct мёртв -> DOWN(net) напрямую, без reconnect.
reset; enq "$EXIT1"; runtick 1000; rm -f "$T/live"; : > "$T/direct"
n=1; while [ "$n" -le 3 ]; do runtick $((1000 + n*60)); n=$((n+1)); done
eq "netdown.phase" "$(sval WD_PHASE)" down
eq "netdown.kind" "$(sval WD_DOWNKIND)" net
has "netdown.stop" "$T/actions" stop
no "netdown.nobounce" "$T/actions" kill

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

# 10b. DOWN(net) -> сеть ожила, сохранённый сервер дохлый, но failover нашёл рабочий -> HEALTHY.
#      Без этого фаза down была терминальной и UI вечно висел на «Starting…».
reset; seed_down net; rm -f "$T/running"; rm -f "$T/live"; : > "$T/failover_ok"
runtick 7000
eq "downfailover.phase" "$(sval WD_PHASE)" healthy
eq "downfailover.kind" "$(sval WD_DOWNKIND)" ""
has "downfailover.did" "$T/actions" failover
has "downfailover.log" "$T/log" "Failover restored VPN"
no "downfailover.nostop" "$T/actions" stop

# 10c. РУЧНАЯ смена сервера снимает backoff: в down с WD_NEXT далеко в будущем новый tag даёт
#      тик сразу (без failover — тег меняет пользователь, не мы).
reset; seed_down vpn; rm -f "$T/running"
sed 's/^WD_NEXT=0$/WD_NEXT=999999/' "$STATE" > "$STATE.x"; mv "$STATE.x" "$STATE"
echo 'Netherlands Amsterdam-2' > "$T/tag"; enq "$EXIT2"
runtick 7000
eq "tagunblock.phase" "$(sval WD_PHASE)" healthy

# 10e. НАШ failover тоже меняет tag (config_apply -> setSelected). Это не выбор пользователя:
#      backoff обязан устоять, иначе полный перебор кандидатов шёл бы раз в минуту вместо 10.
reset; seed_down vpn; rm -f "$T/running"; rm -f "$T/live"
runtick 7000
eq "fobackoff.phase" "$(sval WD_PHASE)" down
eq "fobackoff.next" "$(sval WD_NEXT)" 7060
: > "$T/actions"
runtick 7030
eq "fobackoff.held" "$(cat "$T/actions")" ""
eq "fobackoff.stillnext" "$(sval WD_NEXT)" 7060

# 10f. Прогрессивный backoff в down: 60 -> 120 -> 240 ... с потолком BACKOFF. Плоские 10 минут
#      означали, что вернувшийся через минуту сервер ждал десять.
reset; seed_down vpn; rm -f "$T/running"; rm -f "$T/live"
runtick 7000;  eq "prog.t1" "$(sval WD_NEXT)" 7060
runtick 7060;  eq "prog.t2" "$(sval WD_NEXT)" 7180
runtick 7180;  eq "prog.t3" "$(sval WD_NEXT)" 7420
runtick 7420;  eq "prog.t4" "$(sval WD_NEXT)" 7900
runtick 7900;  eq "prog.cap" "$(sval WD_NEXT)" 8500
runtick 8500;  eq "prog.cap2" "$(sval WD_NEXT)" 9100

# 10h. Лестница отсчитывается от КОНЦА попытки, а не от начала тика. Сама попытка вправе потратить
#      весь DOWN_BUDGET, и пауза, посчитанная от начала, на момент возврата уже была бы в прошлом:
#      следующий cron-тик проходил бы гейт сразу, а LAN висела бы под kill-switch непрерывно.
reset; seed_down vpn; rm -f "$T/running"; rm -f "$T/live"
STOP_DELAY=240
runtick 7000
eq "endanchor.next" "$(sval WD_NEXT)" 7300
STOP_DELAY=0

# 10g. Успешный выход из down обнуляет счётчик: следующий инцидент снова начинает с 60с.
reset; seed_down vpn; rm -f "$T/running"; rm -f "$T/live"
runtick 7000; runtick 7060; runtick 7180
: > "$T/live"; enq "$EXIT1"; runtick 7420
eq "progreset.phase" "$(sval WD_PHASE)" healthy
eq "progreset.tries" "$(sval WD_DOWNTRIES)" 0

# 10d. часы прыгнули назад (NTP): WD_NEXT из далёкого будущего не должен парковать watchdog.
reset; enq "$EXIT1"
{ echo "WD_PHASE=healthy"; echo "WD_FAILS=0"; echo "WD_BASE_IP="; echo "WD_HOME_IP=$HOME_IP"
  echo "WD_TAGSIG=$(sig "$(cat "$T/tag")")"; echo "WD_NEXT=9999999999"; echo "WD_DOWNKIND="; } > "$STATE"
runtick 1000
eq "clockskew.exit" "$(sval WD_BASE_IP)" "$EXIT1"
eq "clockskew.next" "$(sval WD_NEXT)" 1060

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

# 14. selected_tag() читает файл активного сервера; отсутствие файла = пустой тег, а не падение
#     (так выглядит первая загрузка до первого apply).
reset; rm -f "$ACTIVE"
eq "activefile.missing" "$(selected_tag)" ""
printf 'France Paris-9\n' > "$ACTIVE"
eq "activefile.read" "$(selected_tag)" "France Paris-9"

# 15. Путь к файлу тега продублирован в watchdog.sh и в runtime/paths.uc. Разъезд литералов
#     не ловится ничем другим: обе стороны продолжат «работать», просто в разные файлы.
WD_SRC="$SELF_DIR/../../root/usr/share/monkey-business/watchdog.sh"
UC_SRC="$SELF_DIR/../../src/runtime/paths.uc"
eq "activepath.watchdog" "$(grep -c "MB_WD_ACTIVE:-/etc/monkey-business/active" "$WD_SRC")" 1
eq "activepath.rpcd" "$(grep -c "ACTIVE_FILE = CONF_DIR + '/active'" "$UC_SRC")" 1
eq "activepath.confdir" "$(grep -c "CONF_DIR = '/etc/monkey-business'" "$UC_SRC")" 1

# 16. РЕГРЕСС (ставим последним: подменяет now/health_check безвозвратно). Хвост DOWN_BUDGET
#     зарезервирован под failover. Раньше цикл повторов сохранённого конфига выедал бюджет
#     целиком — каждая проба стоит десятки секунд на таймаутах, — failover входил с остатком в
#     единицы секунд, ubus рвался на середине перебора кандидатов и возвращал «не переключились».
#     Итог: фаза down терминальна, вернувшиеся серверы не подхватывались никогда, лечилось только
#     ручным Off/On. Часы здесь идут, в отличие от остальных тестов с замороженным MB_WD_NOW.
reset; seed_down net; rm -f "$T/running"; rm -f "$T/live"; : > "$T/failover_ok"
#     RECOVERY_TRIES=5 (прежний дефолт) + 60с на пробу — ровно тот прожорливый цикл: резерв обязан
#     устоять и при нём.
RECOVERY_TRIES=5
CLOCK=7000
now() { echo "$CLOCK"; }
health_check() { CLOCK=$((CLOCK + 60)); live_probe; }
runtick 7000
eq "budget.phase" "$(sval WD_PHASE)" healthy
has "budget.did" "$T/actions" failover
#     Резерв минус хвост под пост-проверку (её дедлайн отсчитывается от возврата ubus, поэтому
#     перебору отдаётся не весь резерв) — остаток обязан покрывать полный перебор списка.
eq "budget.reserve" \
	"$([ "$(cat "$T/fo_left" 2>/dev/null || echo 0)" \
		-ge "$((FAILOVER_RESERVE - REC_TRIES * (REC_TIMEOUT + 2)))" ] && echo y || echo n)" y

# 17. hysteria — второй процесс того же туннеля. Идёт ПОСЛЕДНИМ: re-source recovery.sh возвращает
#     боевые xray_pids/pidset/vpn_running вместо мок-версий выше. Мёртвый клиент (procd исчерпал
#     respawn: неверный пароль, битая арка) при живом xray не должен читаться как «сервис жив» —
#     иначе лестница бьёт не тот процесс, а UI пишет Connected на туннеле, через который ничего не
#     ходит. Конфиг клиента = признак «активный сервер сейчас hysteria», его пишет rpcd.
reset
MB_WD_HY_CONF="$T/hysteria.json"
# Признак «сервер сейчас hysteria» = конфиг И установленный бинарь: конфиг от прошлого сервера
# переживает переключение, и без второго условия vpn_running ждал бы процесс, которого не бывает.
MB_WD_HY_BIN="$T/hysteria"
: > "$MB_WD_HY_BIN"
chmod 755 "$MB_WD_HY_BIN"
pgrep() {
	case "$*" in
		*"xray run"*) [ -f "$T/xray_up" ] && echo 111 || return 1 ;;
		*"hysteria client"*) [ -f "$T/hy_up" ] && echo 222 || return 1 ;;
		*) return 1 ;;
	esac
}
# shellcheck source=/dev/null
. "$MB_WD_LIB/recovery.sh"
: > "$T/xray_up"
eq "hy.novless" "$(vpn_running && echo y || echo n)" y
: > "$MB_WD_HY_CONF"
eq "hy.dead_client" "$(vpn_running && echo y || echo n)" n
: > "$T/hy_up"
eq "hy.both_alive" "$(vpn_running && echo y || echo n)" y
# Мягкая ступень обязана бить оба процесса: перезапуск одного xray оставил бы аутбаунд смотреть
# в socks мёртвого клиента.
eq "hy.pidset" "$(pidset)" "111 222 "
rm -f "$T/xray_up"
eq "hy.dead_xray" "$(vpn_running && echo y || echo n)" n
# Бинаря нет — конфиг сам по себе не делает туннель hysteria-туннелем: иначе после сноса клиента
# vless-сервер считался бы мёртвым при живом xray.
: > "$T/xray_up"
rm -f "$T/hy_up" "$MB_WD_HY_BIN"
eq "hy.nobin" "$(vpn_running && echo y || echo n)" y

printf '\nwatchdog_test: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
