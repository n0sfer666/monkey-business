#!/bin/sh
# Connectivity watchdog для monkey-business VPN (cron раз в минуту). Сетевые пробы — probes.sh,
# ступени восстановления — recovery.sh, обработчики фаз — phases.sh.
# Reconnect-first: сперва bounce xray (kill-switch держится), и лишь потом init.d stop → direct.
# Env-override (дефолты боевые): FAIL_LIMIT(3) RECONNECT_LIMIT(4) POLL(60) BACKOFF(600)
# EXIT_EVERY(5) REC_TRIES(3) RECOVERY_TRIES(2) RECONNECT_WAIT(5) KILL_WAIT(8) TIMEOUT(10)
# REC_TIMEOUT(6) UBUS_TIMEOUT(90) DOWN_BUDGET(240) FAILOVER_RESERVE(150) DOWN_BACKOFF0(60) — с префиксом
# MB_WD_. MB_WD_NOW(epoch), MB_WD_LIB(каталог probes.sh/phases.sh), MB_WD_ACTIVE(файл тега),
# MB_WD_XRAY_MATCH(cmdline боевого xray), MB_WD_SOURCED=1(тест зовёт tick без main).
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
# Длина лестницы recovery.sh: ступени 0..RECONNECT_LIMIT-1, исчерпали все — down.
RECONNECT_LIMIT="${MB_WD_RECONNECT_LIMIT:-4}"
POLL="${MB_WD_POLL:-60}"
BACKOFF="${MB_WD_BACKOFF:-600}"
EXIT_EVERY="${MB_WD_EXIT_EVERY:-5}"
REC_TRIES="${MB_WD_REC_TRIES:-3}"
RECOVERY_TRIES="${MB_WD_RECOVERY_TRIES:-2}"
RECONNECT_WAIT="${MB_WD_RECONNECT_WAIT:-5}"
# Сколько ждать реальной смерти xray на жёсткой ступени, прежде чем дожать SIGKILL.
KILL_WAIT="${MB_WD_KILL_WAIT:-8}"
TIMEOUT="${MB_WD_TIMEOUT:-10}"
REC_TIMEOUT="${MB_WD_REC_TIMEOUT:-6}"
# дефолтные 30с ubus рвали config_apply на середине перебора кандидатов
UBUS_TIMEOUT="${MB_WD_UBUS_TIMEOUT:-90}"
# Потолок на весь tick_down: пока он идёт, kill-switch поднят и LAN заперт.
DOWN_BUDGET="${MB_WD_DOWN_BUDGET:-240}"
# Хвост бюджета, неприкосновенный для повторов сохранённого конфига: только failover. Без него
# retry-цикл съедал бюджет целиком (5 попыток × ~30с проб с таймаутами), failover входил с
# остатком в единицы секунд, ubus рвался на середине перебора — и фаза down была терминальной:
# раз в BACKOFF поднимался ТОТ ЖЕ мёртвый конфиг. Значение — под полный перебор списка
# (~10с на кандидата) плюс пост-проверка.
FAILOVER_RESERVE="${MB_WD_FAILOVER_RESERVE:-150}"
# Первое ожидание в down. Дальше удвоение до BACKOFF: сервер, вернувшийся через минуту, не должен
# ждать десять.
DOWN_BACKOFF0="${MB_WD_DOWN_BACKOFF0:-60}"
XRAY_MATCH="${MB_WD_XRAY_MATCH:-xray run -c $XRAY_CONF}"
MB_WD_LIB="${MB_WD_LIB:-$(dirname "$0")}"
# Проверяем ВСЕ три: `.` на отсутствующем файле валит скрипт молча, и watchdog умирал бы на каждом
# тике, ничего не оставляя в logread. Достижимо в окне деплоя и при частичном обновлении.
for f in probes.sh recovery.sh phases.sh; do
	[ -f "$MB_WD_LIB/$f" ] || { MB_WD_LIB=/usr/share/monkey-business; break; }
done
# shellcheck source=root/usr/share/monkey-business/probes.sh disable=SC1091
. "$MB_WD_LIB/probes.sh"
# recovery.sh и phases.sh работают по общим WD_* и зовут хелперы ниже: sh резолвит имена при
# вызове, не при сорсинге, поэтому порядок сорсинга и порядок определений не связаны.
# shellcheck source=root/usr/share/monkey-business/recovery.sh disable=SC1091
. "$MB_WD_LIB/recovery.sh"
# shellcheck source=root/usr/share/monkey-business/phases.sh disable=SC1091
. "$MB_WD_LIB/phases.sh"

now() { echo "${MB_WD_NOW:-$(date +%s)}"; }
sig() { printf '%s' "${1:-}" | cksum | cut -d' ' -f1; }
sane() { printf '%s' "${1:-}" | tr -cd 'A-Za-z0-9.:_-'; }
read_intent() { uci -q get "$CONFIG.global.enabled" 2>/dev/null || echo 0; }
selected_tag() { cat "$ACTIVE" 2>/dev/null || echo ''; }

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
	# Исход последнего config_apply, живёт один тик и в state не пишется: нужен только для
	# формулировки лога («переключились на другой сервер» vs «подняли тот же»).
	# shellcheck disable=SC2034
	WD_PROBED=0
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
