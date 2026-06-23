#!/bin/sh
# Connectivity watchdog для monkey-business VPN. Запускается cron'ом раз в минуту.
#
# ЗАЧЕМ: проблема с VPN-сервером не должна валить весь LAN. При kill_switch=1 firewall
# fail-closed — упавший Xray = дроп всего форвардимого трафика. Watchdog детектит провал и
# делает `init.d stop` (flush.sh снимает kill-switch → LAN падает на direct), а затем
# периодически пробует поднять VPN обратно. Так связь не «отражается на устройстве в целом».
#
# КРИТЕРИЙ ЗДОРОВЬЯ: exit-IP через socks (трафик в туннеле) НЕ равен домашнему IP (direct).
# Это буквальное «туннель несёт трафик» — не зависит от geoip, имени сервера и от того, что
# цель пробы попала в direct-лист. Цель — echo-IP сервис, который маршрутизируется через proxy
# (см. PROBE_URLS), с фолбэком на случай отказа одного хоста.
#
# КОНТРАКТ (env-override для тестов; дефолты — боевые):
#   MB_WD_FAIL_LIMIT(5) MB_WD_POLL(60) MB_WD_BACKOFF(600) MB_WD_RECOVERY_TRIES(5)
#   MB_WD_TIMEOUT(10) MB_WD_REC_TIMEOUT(6) MB_WD_LOG_MAX(65536)
#   MB_WD_NOW (epoch override) — для детерминированных тестов.
#   MB_WD_SOURCED=1 — не запускать main (тест переопределяет функции и зовёт tick).
#
# СОСТОЯНИЕ — только в tmpfs (флэш не изнашивается). ЛОГ /usr/local/server.main.log пишется
# ТОЛЬКО на переходах состояний (редко) и ротируется по размеру.
set -u

CONFIG=monkey-business
INIT=/etc/init.d/monkey-business
SOCKS=127.0.0.1:10808
# echo-IP цели (plaintext IP в теле). Должны идти через proxy: НЕ держать в direct-листе.
PROBE_URLS='https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com'

STATE_DIR=/tmp/mb-watchdog
STATE="$STATE_DIR/state"
LOCK="$STATE_DIR/lock"
LOG=/usr/local/server.main.log

FAIL_LIMIT="${MB_WD_FAIL_LIMIT:-5}"
POLL="${MB_WD_POLL:-60}"
BACKOFF="${MB_WD_BACKOFF:-600}"
RECOVERY_TRIES="${MB_WD_RECOVERY_TRIES:-5}"
TIMEOUT="${MB_WD_TIMEOUT:-10}"
REC_TIMEOUT="${MB_WD_REC_TIMEOUT:-6}"
LOG_MAX="${MB_WD_LOG_MAX:-65536}"

now() { echo "${MB_WD_NOW:-$(date +%s)}"; }
sig() { printf '%s' "${1:-}" | cksum | cut -d' ' -f1; }            # стабильный хеш tag (без кавычек)
sane() { printf '%s' "${1:-}" | tr -cd 'A-Za-z0-9.:_-'; }         # безопасно для source state

read_intent() { uci -q get "$CONFIG.global.enabled" 2>/dev/null || echo 0; }
selected_tag() { uci -q get "$CONFIG.selected.server" 2>/dev/null || echo ''; }
vpn_running() { pidof xray >/dev/null 2>&1; }
vpn_start() { $INIT start >/dev/null 2>&1; sleep 5; }
vpn_stop() { $INIT stop >/dev/null 2>&1; }

extract_ip() { printf '%s' "${1:-}" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1; }

# Первый echo-хост, отдавший валидный IPv4. $1 — доп. аргументы curl (напр. -x socks5h://...),
# $2 — таймаут. Форсим -4: домашний и exit-IP сравнимы, xray-аутбаунд дилит по IPv4. Печатает IP.
probe_via() {
	for u in $PROBE_URLS; do
		# shellcheck disable=SC2086
		ip=$(extract_ip "$(curl -s -4 $1 --max-time "$2" "$u" 2>/dev/null)")
		[ -n "$ip" ] && { printf '%s' "$ip"; return; }
	done
}

vpn_probe() { probe_via "-x socks5h://$SOCKS" "$1"; }              # exit-IP через туннель
direct_probe() { probe_via "" "$TIMEOUT"; }                       # домашний (direct) IP

log_event() {
	mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
	sz=$(wc -c < "$LOG" 2>/dev/null || echo 0)
	if [ "${sz:-0}" -gt "$LOG_MAX" ]; then
		tail -c $((LOG_MAX / 2)) "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
	fi
	echo "$(date '+%F %T') [mb-watchdog] $1" >> "$LOG"
}

load_state() {
	WD_PHASE=healthy; WD_FAILS=0; WD_BASE_IP=; WD_HOME_IP=; WD_TAGSIG=0; WD_NEXT=0; WD_DOWNKIND=
	# shellcheck disable=SC1090
	[ -f "$STATE" ] && . "$STATE"
}

save_state() {
	{
		echo "WD_PHASE=$(sane "$WD_PHASE")"
		echo "WD_FAILS=$(sane "$WD_FAILS")"
		echo "WD_BASE_IP=$(sane "$WD_BASE_IP")"
		echo "WD_HOME_IP=$(sane "$WD_HOME_IP")"
		echo "WD_TAGSIG=$(sane "$WD_TAGSIG")"
		echo "WD_NEXT=$(sane "$WD_NEXT")"
		echo "WD_DOWNKIND=$(sane "$WD_DOWNKIND")"
	} > "$STATE"
}

# Здоров, если exit-IP валиден И отличается от домашнего (трафик реально в туннеле, не утёк
# direct). Пустой WD_HOME_IP (домашний ещё не известен) → принять любой валидный exit-IP.
# Печатает "ok <ip>" | "fail".
eval_exit() {
	ip=$(sane "${1:-}")
	[ -n "$ip" ] || { echo fail; return; }
	[ -n "$WD_HOME_IP" ] && [ "$ip" = "$WD_HOME_IP" ] && { echo fail; return; }
	echo "ok $ip"
}

refresh_home() { h=$(direct_probe); [ -n "$h" ] && WD_HOME_IP=$(sane "$h"); }

tick() {
	[ "$(read_intent)" = 1 ] || { rm -f "$STATE" 2>/dev/null || true; return 0; }

	load_state
	t=$(now)
	[ "$t" -lt "$WD_NEXT" ] && return 0

	tagsig=$(sig "$(selected_tag)")
	if [ "$tagsig" != "$WD_TAGSIG" ]; then
		WD_TAGSIG=$tagsig; WD_BASE_IP=; WD_FAILS=0; WD_PHASE=healthy
	fi

	case "$WD_PHASE" in
		healthy) tick_healthy ;;
		down)    tick_down ;;
		*)       WD_PHASE=healthy; WD_NEXT=$((t + POLL)) ;;
	esac
	save_state
}

tick_healthy() {
	vpn_running || vpn_start
	refresh_home
	res=$(eval_exit "$(vpn_probe "$TIMEOUT")")

	if [ "${res%% *}" = ok ]; then
		WD_BASE_IP=${res#ok }
		WD_FAILS=0; WD_NEXT=$((t + POLL))
		return
	fi

	WD_FAILS=$((WD_FAILS + 1))
	if [ "$WD_FAILS" -lt "$FAIL_LIMIT" ]; then
		WD_NEXT=$((t + POLL)); return
	fi

	vpn_stop
	if [ -n "$(direct_probe)" ]; then
		WD_DOWNKIND=vpn
		log_event "VPN exit failing ${FAIL_LIMIT}x (home ${WD_HOME_IP:-?}, last exit ${WD_BASE_IP:-?}). VPN stopped, LAN on direct."
	else
		WD_DOWNKIND=net
		log_event "No connectivity: VPN and direct probes both failing. VPN stopped."
	fi
	WD_PHASE=down; WD_FAILS=0; WD_NEXT=$((t + BACKOFF))
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
		res=$(eval_exit "$(vpn_probe "$REC_TIMEOUT")")
		if [ "${res%% *}" = ok ]; then
			WD_BASE_IP=${res#ok }; ok=1; break
		fi
		i=$((i + 1)); sleep 2
	done

	if [ "$ok" = 1 ]; then
		log_event "VPN restored (exit ${WD_BASE_IP:-?}). Resuming monitoring."
		WD_PHASE=healthy; WD_FAILS=0; WD_DOWNKIND=; WD_NEXT=$((t + POLL))
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
