#!/bin/sh
# Connectivity watchdog для monkey-business VPN (cron раз в минуту). Стратегия и машина состояний
# — .context/notes/watchdog.md; сетевые пробы — probes.sh. Reconnect-first: при провале сперва
# bounce xray (kill-switch держится), и лишь если не помогло — init.d stop → LAN на direct.
# Env-override (дефолты боевые): FAIL_LIMIT(3) RECONNECT_LIMIT(2) POLL(60) BACKOFF(600)
# EXIT_EVERY(5) REC_TRIES(3) RECOVERY_TRIES(2) RECONNECT_WAIT(5) TIMEOUT(10) REC_TIMEOUT(6)
# UBUS_TIMEOUT(90) DOWN_BUDGET(240) FAILOVER_RESERVE(150) DOWN_BACKOFF0(60) — все с префиксом
# MB_WD_. MB_WD_NOW(epoch),
# MB_WD_LIB(каталог probes.sh), MB_WD_XRAY_MATCH(cmdline боевого xray), MB_WD_ACTIVE(файл тега),
# MB_WD_SOURCED=1(тест зовёт tick без main).
set -u

CONFIG=monkey-business
INIT=/etc/init.d/monkey-business
XRAY_CONF=/etc/monkey-business/xray.json
STATE_DIR=/tmp/mb-watchdog
STATE="$STATE_DIR/state"
LOCK="$STATE_DIR/lock"
# Активный сервер: тег пишет rpcd рядом с xray.json (см. setSelected). Читаем файл, а не
# uci — в UCI этого состояния больше нет, оно рантайм, а не выбор пользователя.
# Путь продублирован в root/usr/share/rpcd/ucode/monkey-business.uc (ACTIVE_FILE) — расхождение
# ловит watchdog_test (тег молча стал бы вечно пустым, и фаза перестала бы реагировать).
ACTIVE="${MB_WD_ACTIVE:-/etc/monkey-business/active}"

FAIL_LIMIT="${MB_WD_FAIL_LIMIT:-3}"
RECONNECT_LIMIT="${MB_WD_RECONNECT_LIMIT:-2}"
POLL="${MB_WD_POLL:-60}"
BACKOFF="${MB_WD_BACKOFF:-600}"
EXIT_EVERY="${MB_WD_EXIT_EVERY:-5}"
REC_TRIES="${MB_WD_REC_TRIES:-3}"
RECOVERY_TRIES="${MB_WD_RECOVERY_TRIES:-2}"
RECONNECT_WAIT="${MB_WD_RECONNECT_WAIT:-5}"
TIMEOUT="${MB_WD_TIMEOUT:-10}"
REC_TIMEOUT="${MB_WD_REC_TIMEOUT:-6}"
# дефолтные 30с ubus рвали config_apply на середине перебора кандидатов
UBUS_TIMEOUT="${MB_WD_UBUS_TIMEOUT:-90}"
# Потолок на весь tick_down: пока он идёт, kill-switch поднят и LAN заперт.
DOWN_BUDGET="${MB_WD_DOWN_BUDGET:-240}"
# Хвост бюджета, неприкосновенный для повторов сохранённого конфига: только failover. Без него
# retry-цикл съедал бюджет целиком (5 попыток × ~30с проб с таймаутами), failover входил с
# остатком в единицы секунд, ubus рвался на середине перебора кандидатов — и фаза down была
# терминальной: раз в BACKOFF поднимался ТОТ ЖЕ мёртвый конфиг, а рабочие серверы не пробовались
# никогда. Значение — под полный перебор списка (~10с на кандидата) плюс пост-проверка.
FAILOVER_RESERVE="${MB_WD_FAILOVER_RESERVE:-150}"
# Первое ожидание в down. Дальше удвоение до BACKOFF: сервер, вернувшийся через минуту, не должен
# ждать десять.
DOWN_BACKOFF0="${MB_WD_DOWN_BACKOFF0:-60}"
XRAY_MATCH="${MB_WD_XRAY_MATCH:-xray run -c $XRAY_CONF}"
MB_WD_LIB="${MB_WD_LIB:-$(dirname "$0")}"
[ -f "$MB_WD_LIB/probes.sh" ] || MB_WD_LIB=/usr/share/monkey-business
# shellcheck source=root/usr/share/monkey-business/probes.sh disable=SC1091
. "$MB_WD_LIB/probes.sh"

now() { echo "${MB_WD_NOW:-$(date +%s)}"; }
sig() { printf '%s' "${1:-}" | cksum | cut -d' ' -f1; }
sane() { printf '%s' "${1:-}" | tr -cd 'A-Za-z0-9.:_-'; }
read_intent() { uci -q get "$CONFIG.global.enabled" 2>/dev/null || echo 0; }
selected_tag() { cat "$ACTIVE" 2>/dev/null || echo ''; }
# Матч по cmdline боевого конфига, а не `pidof xray`: иначе эфемерная проба failover
# (/tmp/mb-probe.json) и чужой xray из стокового пакета считаются «сервис жив».
# Без pgrep (урезанный busybox) деградируем до pidof: грубее, но лучше вечного «сервис мёртв».
if command -v pgrep >/dev/null 2>&1; then
	xray_pids() { pgrep -f "$XRAY_MATCH"; }
else
	xray_pids() { pidof xray; }
fi
vpn_running() { xray_pids >/dev/null 2>&1; }
vpn_start() { $INIT start >/dev/null 2>&1; sleep 5; }
vpn_stop() { $INIT stop >/dev/null 2>&1; }
vpn_reconnect() {
	# shellcheck disable=SC2046
	kill $(xray_pids) 2>/dev/null || true
	sleep "$RECONNECT_WAIT"
	vpn_running || vpn_start
}
# Failover: rpcd пересобирает конфиг на ПЕРВЫЙ рабочий сервер по приоритету (config_apply ->
# selectWorking с реальными эфемерными пробами). probed:true = нашёлся сервер, прошедший пробу.
# Возврат 0 = переключились (сервис уже перезапущен с новым сервером). Имя-агностично.
# $1 — потолок ожидания ubus в секундах (по умолчанию UBUS_TIMEOUT); tick_down зажимает его
# остатком своего бюджета, чтобы kill-switch не висел дольше обещанного.
failover_switch() {
	res=$(ubus -t "${1:-$UBUS_TIMEOUT}" call "$CONFIG" config_apply 2>/dev/null) || return 1
	printf '%s' "$res" | grep -q '"probed": *true'
}
# config_apply в ЛЮБОМ исходе зовёт setSelected, т.е. тег меняем мы сами. Без пересинхронизации
# WD_TAGSIG следующий тик принял бы это за ручной выбор пользователя, сбросил фазу и обнулил
# backoff — вместо отдыха в 10 минут получился бы полный перебор кандидатов раз в минуту.
try_failover() {
	failover_switch "$@"; fo=$?
	WD_TAGSIG=$(sig "$(selected_tag)")
	return "$fo"
}

# syslog вместо своего файла на rootfs: ring buffer в RAM. Прошлый вариант дописывал и ротировал
# файл на карте при каждом инциденте — а инциденты идут именно тогда, когда сеть лежит и watchdog
# тикает каждую минуту, т.е. запись на флеш была тем интенсивнее, чем хуже дела.
# Тег mb-event отдельный от monkey-business: под общим тегом init.d сыплет служебные строки
# apply.sh/flush.sh на каждый старт-стоп, и «последним событием» в UI всегда оказывались они,
# а не причина отказа.
log_event() { logger -t mb-event "watchdog: $1"; }

load_state() {
	WD_PHASE=healthy; WD_FAILS=0; WD_BASE_IP=; WD_HOME_IP=; WD_TAGSIG=0; WD_NEXT=0
	WD_DOWNKIND=; WD_RECTRIES=0; WD_EXITDUE=0; WD_DOWNTRIES=0
	# shellcheck disable=SC1090
	[ -f "$STATE" ] && . "$STATE"
	# Состояние от версии без счётчика: sourcing оставит переменную неопределённой, а set -u
	# уронит первый же tick_down.
	WD_DOWNTRIES="${WD_DOWNTRIES:-0}"
}
save_state() {
	printf 'WD_PHASE=%s\nWD_FAILS=%s\nWD_BASE_IP=%s\nWD_HOME_IP=%s\nWD_TAGSIG=%s\nWD_NEXT=%s\nWD_DOWNKIND=%s\nWD_RECTRIES=%s\nWD_EXITDUE=%s\nWD_DOWNTRIES=%s\n' \
		"$(sane "$WD_PHASE")" "$(sane "$WD_FAILS")" "$(sane "$WD_BASE_IP")" "$(sane "$WD_HOME_IP")" \
		"$(sane "$WD_TAGSIG")" "$(sane "$WD_NEXT")" "$(sane "$WD_DOWNKIND")" "$(sane "$WD_RECTRIES")" \
		"$(sane "$WD_EXITDUE")" "$(sane "$WD_DOWNTRIES")" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
}

# Ожидание до следующей попытки в down: DOWN_BACKOFF0 с удвоением до потолка BACKOFF.
down_backoff() {
	WD_DOWNTRIES=$((WD_DOWNTRIES + 1))
	d="$DOWN_BACKOFF0"; i=1
	while [ "$i" -lt "$WD_DOWNTRIES" ] && [ "$d" -lt "$BACKOFF" ]; do d=$((d * 2)); i=$((i + 1)); done
	[ "$d" -gt "$BACKOFF" ] && d="$BACKOFF"
	WD_NEXT=$((t + d))
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

	# Смена сервера — выше backoff-гейта: иначе выбор пользователя ждал бы до BACKOFF.
	tagsig=$(sig "$(selected_tag)")
	if [ "$tagsig" != "$WD_TAGSIG" ]; then
		WD_TAGSIG=$tagsig; WD_BASE_IP=; WD_FAILS=0; WD_RECTRIES=0; WD_EXITDUE=0
		WD_DOWNKIND=; WD_PHASE=healthy; WD_NEXT=0; WD_DOWNTRIES=0
	fi

	# R2S без RTC: после NTP часы прыгают, и абсолютный WD_NEXT из будущего запарковал бы
	# watchdog на часы. Окно ожидания не может быть длиннее BACKOFF.
	[ "$WD_NEXT" -gt $((t + BACKOFF)) ] && WD_NEXT=0
	[ "$t" -lt "$WD_NEXT" ] && return 0

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
		WD_PHASE=down; WD_FAILS=0; WD_DOWNTRIES=0; down_backoff; return
	fi

	WD_DOWNKIND=vpn
	log_event "VPN exit failing ${FAIL_LIMIT}x (home ${WD_HOME_IP:-?}, last exit ${WD_BASE_IP:-?}). Reconnecting (kill-switch held)."
	WD_PHASE=reconnecting; WD_RECTRIES=0; WD_FAILS=0; WD_NEXT=$t
}

tick_reconnecting() {
	if [ -z "$(direct_probe)" ]; then
		vpn_stop; WD_DOWNKIND=net
		log_event "Network down during reconnect. VPN stopped, LAN on direct."
		WD_PHASE=down; WD_DOWNTRIES=0; down_backoff; return
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
	if try_failover; then
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
	WD_PHASE=down; WD_RECTRIES=0; WD_DOWNTRIES=0; down_backoff
}

tick_down() {
	home_now=$(direct_probe)
	if [ -z "$home_now" ]; then
		[ "$WD_DOWNKIND" = vpn ] && { log_event "Network now fully down (direct probe lost)."; WD_DOWNKIND=net; }
		down_backoff; return
	fi
	WD_HOME_IP=$(sane "$home_now")

	[ "$WD_DOWNKIND" = net ] && log_event "Network recovered (direct ok). Attempting VPN."

	deadline=$((t + DOWN_BUDGET))
	# Повторам сохранённого конфига достаётся только голова бюджета — хвост FAILOVER_RESERVE
	# принадлежит перебору серверов и не может быть у него отобран.
	retry_deadline=$((deadline - FAILOVER_RESERVE))
	vpn_start
	i=0; ok=0
	while [ "$i" -lt "$RECOVERY_TRIES" ] && [ "$(now)" -lt "$retry_deadline" ]; do
		if health_check 1 "$REC_TIMEOUT"; then ok=1; break; fi
		i=$((i + 1)); sleep 2
	done

	if [ "$ok" = 1 ]; then
		log_event "VPN restored (exit ${WD_BASE_IP:-?}). Resuming monitoring."
		WD_PHASE=healthy; WD_FAILS=0; WD_RECTRIES=0; WD_DOWNKIND=; WD_DOWNTRIES=0; WD_NEXT=$((t + POLL))
		return
	fi

	# Сохранённый в конфиге сервер мёртв — без failover фаза down была терминальной: раз в
	# BACKOFF поднимали тот же дохлый конфиг и снова гасили (UI вечно «Starting…»).
	# ubus и пост-проверка тоже внутри бюджета: без клампа вход в failover на deadline-1 давал бы
	# ещё UBUS_TIMEOUT + REC_TRIES*(REC_TIMEOUT+2) сверху, т.е. LAN заперта дольше обещанного.
	# Пол FAILOVER_RESERVE: retry-цикл выше упёрся в retry_deadline, так что остаток не меньше
	# резерва, но при съехавших часах кламп не должен опуститься до нерабочих секунд.
	left=$((deadline - $(now)))
	[ "$left" -lt "$FAILOVER_RESERVE" ] && left="$FAILOVER_RESERVE"
	deadline=$(( $(now) + left ))
	if try_failover "$left"; then
		i=0
		while [ "$i" -lt "$REC_TRIES" ] && [ "$(now)" -lt "$deadline" ]; do
			if health_check 1 "$REC_TIMEOUT"; then
				log_event "Failover restored VPN (exit ${WD_BASE_IP:-?}). Resuming monitoring."
				WD_PHASE=healthy; WD_FAILS=0; WD_RECTRIES=0; WD_DOWNKIND=; WD_DOWNTRIES=0; WD_NEXT=$((t + POLL))
				return
			fi
			i=$((i + 1)); sleep 2
		done
	fi

	vpn_stop
	[ "$WD_DOWNKIND" != vpn ] && log_event "Network up but VPN still failing. Staying on direct."
	WD_DOWNKIND=vpn; down_backoff
}

main() {
	mkdir -p "$STATE_DIR" 2>/dev/null || true
	if command -v flock >/dev/null 2>&1; then
		exec 9>"$LOCK"
		flock -n 9 || exit 0
	else
		# Без flock cron-тики наслаивались (tick спит до ~90с) и гонка портила state.
		# mkdir атомарен; протухший лок (>15 мин) снимаем, иначе watchdog умрёт навсегда.
		# Гонка на снятии протухшего лока безопасна: тики раз в минуту, а победитель сразу
		# обновляет mtime каталога — второй претендент уже не увидит его протухшим.
		if ! mkdir "$LOCK.d" 2>/dev/null; then
			age=$(stat -c %Y "$LOCK.d" 2>/dev/null || echo 0)
			[ "$(( $(date +%s) - age ))" -gt 900 ] || exit 0
			rmdir "$LOCK.d" 2>/dev/null
			mkdir "$LOCK.d" 2>/dev/null || exit 0
		fi
		trap 'rmdir "$LOCK.d" 2>/dev/null' EXIT
		trap 'rmdir "$LOCK.d" 2>/dev/null; exit 143' INT TERM
	fi
	tick
}

[ "${MB_WD_SOURCED:-0}" = 1 ] || main
