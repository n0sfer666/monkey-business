#!/bin/sh
# Connectivity watchdog для monkey-business VPN (cron раз в минуту). Стратегия и машина состояний
# — .context/notes/watchdog.md; сетевые пробы — probes.sh. Reconnect-first: при провале сперва
# bounce xray (kill-switch держится), и лишь если не помогло — init.d stop → LAN на direct.
# Env-override (дефолты боевые): FAIL_LIMIT(3) RECONNECT_LIMIT(2) POLL(60) BACKOFF(600)
# EXIT_EVERY(5) REC_TRIES(3) RECOVERY_TRIES(5) RECONNECT_WAIT(5) TIMEOUT(10) REC_TIMEOUT(6)
# LOG_MAX(65536) — все с префиксом MB_WD_. MB_WD_NOW(epoch), MB_WD_LIB(каталог probes.sh),
# MB_WD_SOURCED=1(тест зовёт tick без main).
set -u

CONFIG=monkey-business
INIT=/etc/init.d/monkey-business
STATE_DIR=/tmp/mb-watchdog
STATE="$STATE_DIR/state"
LOCK="$STATE_DIR/lock"
LOG=/usr/local/server.main.log

FAIL_LIMIT="${MB_WD_FAIL_LIMIT:-3}"
RECONNECT_LIMIT="${MB_WD_RECONNECT_LIMIT:-2}"
POLL="${MB_WD_POLL:-60}"
BACKOFF="${MB_WD_BACKOFF:-600}"
EXIT_EVERY="${MB_WD_EXIT_EVERY:-5}"
REC_TRIES="${MB_WD_REC_TRIES:-3}"
RECOVERY_TRIES="${MB_WD_RECOVERY_TRIES:-5}"
RECONNECT_WAIT="${MB_WD_RECONNECT_WAIT:-5}"
TIMEOUT="${MB_WD_TIMEOUT:-10}"
REC_TIMEOUT="${MB_WD_REC_TIMEOUT:-6}"
LOG_MAX="${MB_WD_LOG_MAX:-65536}"
MB_WD_LIB="${MB_WD_LIB:-$(dirname "$0")}"
[ -f "$MB_WD_LIB/probes.sh" ] || MB_WD_LIB=/usr/share/monkey-business
# shellcheck source=root/usr/share/monkey-business/probes.sh disable=SC1091
. "$MB_WD_LIB/probes.sh"

now() { echo "${MB_WD_NOW:-$(date +%s)}"; }
sig() { printf '%s' "${1:-}" | cksum | cut -d' ' -f1; }
sane() { printf '%s' "${1:-}" | tr -cd 'A-Za-z0-9.:_-'; }
read_intent() { uci -q get "$CONFIG.global.enabled" 2>/dev/null || echo 0; }
selected_tag() { uci -q get "$CONFIG.selected.server" 2>/dev/null || echo ''; }
vpn_running() { pidof xray >/dev/null 2>&1; }
vpn_start() { $INIT start >/dev/null 2>&1; sleep 5; }
vpn_stop() { $INIT stop >/dev/null 2>&1; }
vpn_reconnect() {
	# shellcheck disable=SC2046
	kill $(pidof xray) 2>/dev/null || true
	sleep "$RECONNECT_WAIT"
	vpn_running || vpn_start
}
# Failover: rpcd пересобирает конфиг на ПЕРВЫЙ рабочий сервер по приоритету (config_apply ->
# selectWorking с реальными эфемерными пробами). probed:true = нашёлся сервер, прошедший пробу.
# Возврат 0 = переключились (сервис уже перезапущен с новым сервером). Имя-агностично.
failover_switch() {
	res=$(ubus call "$CONFIG" config_apply 2>/dev/null) || return 1
	printf '%s' "$res" | grep -q '"probed": *true'
}

log_event() {
	mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
	sz=$(wc -c < "$LOG" 2>/dev/null || echo 0)
	if [ "${sz:-0}" -gt "$LOG_MAX" ]; then
		tail -c $((LOG_MAX / 2)) "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
	fi
	echo "$(date '+%F %T') [mb-watchdog] $1" >> "$LOG"
}

load_state() {
	WD_PHASE=healthy; WD_FAILS=0; WD_BASE_IP=; WD_HOME_IP=; WD_TAGSIG=0; WD_NEXT=0
	WD_DOWNKIND=; WD_RECTRIES=0; WD_EXITDUE=0
	# shellcheck disable=SC1090
	[ -f "$STATE" ] && . "$STATE"
}
save_state() {
	printf 'WD_PHASE=%s\nWD_FAILS=%s\nWD_BASE_IP=%s\nWD_HOME_IP=%s\nWD_TAGSIG=%s\nWD_NEXT=%s\nWD_DOWNKIND=%s\nWD_RECTRIES=%s\nWD_EXITDUE=%s\n' \
		"$(sane "$WD_PHASE")" "$(sane "$WD_FAILS")" "$(sane "$WD_BASE_IP")" "$(sane "$WD_HOME_IP")" \
		"$(sane "$WD_TAGSIG")" "$(sane "$WD_NEXT")" "$(sane "$WD_DOWNKIND")" "$(sane "$WD_RECTRIES")" \
		"$(sane "$WD_EXITDUE")" > "$STATE"
}

# Здоров, если exit-IP валиден И отличается от домашнего; пустой WD_HOME_IP → любой валидный.
eval_exit() {
	ip=$(sane "${1:-}")
	[ -n "$ip" ] || { echo fail; return; }
	[ -n "$WD_HOME_IP" ] && [ "$ip" = "$WD_HOME_IP" ] && { echo fail; return; }
	echo "ok $ip"
}
refresh_home() { h=$(direct_probe); [ -n "$h" ] && WD_HOME_IP=$(sane "$h"); }

# 0 — здоров. liveness обязателен; exit-IP сверка при force ($1=1) или раз в EXIT_EVERY циклов.
health_check() {
	live_probe || return 1
	WD_EXITDUE=$((WD_EXITDUE + 1))
	if [ "${1:-0}" = 1 ] || [ "$WD_EXITDUE" -ge "$EXIT_EVERY" ]; then
		WD_EXITDUE=0
		refresh_home
		res=$(eval_exit "$(vpn_probe "${2:-$TIMEOUT}")")
		[ "${res%% *}" = ok ] || return 1
		WD_BASE_IP=${res#ok }
	fi
	return 0
}
tick() {
	[ "$(read_intent)" = 1 ] || { rm -f "$STATE" 2>/dev/null || true; return 0; }

	load_state
	t=$(now)
	[ "$t" -lt "$WD_NEXT" ] && return 0

	tagsig=$(sig "$(selected_tag)")
	if [ "$tagsig" != "$WD_TAGSIG" ]; then
		WD_TAGSIG=$tagsig; WD_BASE_IP=; WD_FAILS=0; WD_RECTRIES=0; WD_EXITDUE=0; WD_PHASE=healthy
	fi

	case "$WD_PHASE" in
		healthy)      tick_healthy ;;
		reconnecting) tick_reconnecting ;;
		down)         tick_down ;;
		*)            WD_PHASE=healthy; WD_NEXT=$((t + POLL)) ;;
	esac
	save_state
}

tick_healthy() {
	vpn_running || vpn_start

	if health_check 0; then
		WD_FAILS=0; WD_NEXT=$((t + POLL)); return
	fi

	WD_FAILS=$((WD_FAILS + 1))
	if [ "$WD_FAILS" -lt "$FAIL_LIMIT" ]; then
		WD_NEXT=$((t + POLL)); return
	fi

	if [ -z "$(direct_probe)" ]; then
		vpn_stop; WD_DOWNKIND=net
		log_event "No connectivity: VPN and direct probes both failing. VPN stopped."
		WD_PHASE=down; WD_FAILS=0; WD_NEXT=$((t + BACKOFF)); return
	fi

	WD_DOWNKIND=vpn
	log_event "VPN exit failing ${FAIL_LIMIT}x (home ${WD_HOME_IP:-?}, last exit ${WD_BASE_IP:-?}). Reconnecting (kill-switch held)."
	WD_PHASE=reconnecting; WD_RECTRIES=0; WD_FAILS=0; WD_NEXT=$t
}

tick_reconnecting() {
	if [ -z "$(direct_probe)" ]; then
		vpn_stop; WD_DOWNKIND=net
		log_event "Network down during reconnect. VPN stopped, LAN on direct."
		WD_PHASE=down; WD_NEXT=$((t + BACKOFF)); return
	fi

	vpn_reconnect
	i=0
	while [ "$i" -lt "$REC_TRIES" ]; do
		if health_check 1 "$REC_TIMEOUT"; then
			log_event "VPN reconnected (exit ${WD_BASE_IP:-?}). Resuming monitoring."
			WD_PHASE=healthy; WD_FAILS=0; WD_RECTRIES=0; WD_NEXT=$((t + POLL)); return
		fi
		i=$((i + 1)); sleep 2
	done

	WD_RECTRIES=$((WD_RECTRIES + 1))
	if [ "$WD_RECTRIES" -lt "$RECONNECT_LIMIT" ]; then
		WD_NEXT=$((t + POLL)); return
	fi

	# Текущий сервер устойчиво не поднимается -> failover на следующий рабочий по приоритету.
	# config_apply сам пробует кандидатов и перезапускает сервис; подтверждаем health-проверкой.
	if failover_switch; then
		i=0
		while [ "$i" -lt "$REC_TRIES" ]; do
			if health_check 1 "$REC_TIMEOUT"; then
				log_event "Failover switched server (exit ${WD_BASE_IP:-?}). Resuming monitoring."
				WD_PHASE=healthy; WD_FAILS=0; WD_RECTRIES=0; WD_NEXT=$((t + POLL)); return
			fi
			i=$((i + 1)); sleep 2
		done
	fi

	vpn_stop; WD_DOWNKIND=vpn
	log_event "Reconnect failed ${RECONNECT_LIMIT}x (no working failover server). VPN stopped, LAN on direct."
	WD_PHASE=down; WD_RECTRIES=0; WD_NEXT=$((t + BACKOFF))
}

tick_down() {
	home_now=$(direct_probe)
	if [ -z "$home_now" ]; then
		[ "$WD_DOWNKIND" = vpn ] && { log_event "Network now fully down (direct probe lost)."; WD_DOWNKIND=net; }
		WD_NEXT=$((t + BACKOFF)); return
	fi
	WD_HOME_IP=$(sane "$home_now")

	[ "$WD_DOWNKIND" = net ] && log_event "Network recovered (direct ok). Attempting VPN."

	vpn_start
	i=0; ok=0
	while [ "$i" -lt "$RECOVERY_TRIES" ]; do
		if health_check 1 "$REC_TIMEOUT"; then ok=1; break; fi
		i=$((i + 1)); sleep 2
	done

	if [ "$ok" = 1 ]; then
		log_event "VPN restored (exit ${WD_BASE_IP:-?}). Resuming monitoring."
		WD_PHASE=healthy; WD_FAILS=0; WD_RECTRIES=0; WD_DOWNKIND=; WD_NEXT=$((t + POLL))
	else
		vpn_stop
		[ "$WD_DOWNKIND" != vpn ] && log_event "Network up but VPN still failing. Staying on direct."
		WD_DOWNKIND=vpn; WD_NEXT=$((t + BACKOFF))
	fi
}

main() {
	mkdir -p "$STATE_DIR" 2>/dev/null || true
	if command -v flock >/dev/null 2>&1; then
		exec 9>"$LOCK"
		flock -n 9 || exit 0
	fi
	tick
}

[ "${MB_WD_SOURCED:-0}" = 1 ] || main
