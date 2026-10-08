#!/bin/sh
# Автообновление подписки (cron раз в минуту, частоту гейтит сам по update_interval).
# Делает ровно то же, что кнопка "Fetch subscription" в LuCI: тянет список серверов и сохраняет,
# сохраняя ручной порядок (см. mergeKeepingOrder). Перечитать конфиг xray НЕ заставляет — это
# дело Apply/watchdog: рвать рабочий туннель ради обновления списка дороже, чем дождаться
# ближайшего применения.
#
# Состояние в tmpfs: после ребута обновляемся один раз лишний — зато не жжём SD-карту записью
# раз в сутки в одни и те же LBA (ровно за это выпилили boothealth beat).
#
# Env-override (дефолты боевые): MB_SUB_STATE_DIR(/tmp/mb-subupdate) MB_SUB_RETRY(900)
# MB_SUB_MIN(300) MB_SUB_UBUS_TIMEOUT(60) MB_SUB_NOW(epoch) MB_SUB_WD_LOCK(/tmp/mb-watchdog/lock)
# MB_SUB_LOCK_WAIT(30) MB_SUB_SWITCH_TIMEOUT(90) MB_SUB_APPLY_MARGIN(15) MB_SUB_LIB(каталог wdlock.sh).
set -u

CONFIG=monkey-business
STATE_DIR="${MB_SUB_STATE_DIR:-/tmp/mb-subupdate}"
# Пауза после неудачи: панель недоступна (нет сети, VPN лежит) — это норма, но долбиться к ней
# каждую минуту нельзя.
RETRY="${MB_SUB_RETRY:-900}"
# Нижняя граница интервала: опечатка в поле формы (10 вместо 86400) не должна превращаться
# в обстрел панели.
MIN="${MB_SUB_MIN:-300}"
UBUS_TIMEOUT="${MB_SUB_UBUS_TIMEOUT:-60}"
NOW="${MB_SUB_NOW:-$(date +%s)}"
WD_LOCK="${MB_SUB_WD_LOCK:-/tmp/mb-watchdog/lock}"
LOCK_WAIT="${MB_SUB_LOCK_WAIT:-30}"
SWITCH_TIMEOUT="${MB_SUB_SWITCH_TIMEOUT:-90}"
APPLY_MARGIN="${MB_SUB_APPLY_MARGIN:-15}"
MB_SUB_LIB="${MB_SUB_LIB:-$(dirname "$0")}"
[ -f "$MB_SUB_LIB/wdlock.sh" ] || MB_SUB_LIB=/usr/share/monkey-business
# shellcheck source=root/usr/share/monkey-business/wdlock.sh disable=SC1091
. "$MB_SUB_LIB/wdlock.sh"

log() { logger -t mb-subupdate "$@" 2>/dev/null || true; }
cfg() { uci -q get "$CONFIG.$1.$2" 2>/dev/null || echo ""; }
now() { echo "${MB_SUB_NOW:-$(date +%s)}"; }
# нечисло -> дефолт: пустой или битый uci не должен ронять арифметику, иначе скрипт молча
# умирал бы на каждом тике
num() { case "${1:-}" in '' | *[!0-9]*) echo "$2" ;; *) echo "$1" ;; esac; }
# Логируем только числа и фиксированные строки ошибок: errors[] из парсера содержит обрезанные
# строки подписки, а в них uuid/пароли — в syslog им не место.
field() { echo "$2" | sed -n "s/.*\"$1\"[ 	]*:[ 	]*\"\{0,1\}\([^\",}]*\).*/\1/p"; }

subscriptions() {
	uci -q -X show "$CONFIG" 2>/dev/null | sed -n "s/^$CONFIG\.\([A-Za-z0-9_-]*\)=subscription$/\1/p"
}

update_one() {
	id=$1
	state="$STATE_DIR/$id"
	[ "$(cfg "$id" auto_update)" = 1 ] || return 0
	[ -n "$(cfg "$id" url)" ] || return 0

	interval=$(num "$(cfg "$id" update_interval)" 86400)
	[ "$interval" -ge "$MIN" ] || interval="$MIN"

	last=0
	result=""
	read -r last result 2>/dev/null <"$state" || true
	last=$(num "${last:-0}" 0)
	result="${result:-}"
	# часы прыгнули назад (NTP выставил время после загрузки из 1970) -> считаем, что пора
	[ "$NOW" -ge "$last" ] || last=0

	due="$interval"
	[ "$result" = ok ] || due="$RETRY"
	[ "$last" -eq 0 ] || [ $((NOW - last)) -ge "$due" ] || return 0

	mkdir -p "$STATE_DIR" 2>/dev/null || return 1
	# Штамп ДО вызова: тик занимает до UBUS_TIMEOUT секунд, а cron придёт через минуту — без этого
	# следующий тик начал бы второе обновление поверх незакончившегося первого.
	printf '%s run\n' "$NOW" >"$state"

	res=$(ubus -t "$UBUS_TIMEOUT" call "$CONFIG" subscription_update "{\"sub\":\"$id\"}" 2>/dev/null) || res=""
	flat=$(echo "$res" | tr -d '\n\t')

	if [ -z "$flat" ]; then
		printf '%s fail\n' "$NOW" >"$state"
		log "подписка $id не обновлена: rpcd не ответил"
		return 1
	fi

	case "$flat" in
		*'"error"'*)
			printf '%s fail\n' "$NOW" >"$state"
			log "подписка $id не обновлена: $(field error "$flat")"
			return 1
			;;
	esac

	printf '%s ok\n' "$NOW" >"$state"
	log "подписка $id обновлена: серверов $(field added "$flat")"
}

autoswitch() {
	res=$(ubus -t "$UBUS_TIMEOUT" call "$CONFIG" subscription_autoswitch '{"check":true}' 2>/dev/null) || return 0
	case "$res" in *'"switch_to"'*) ;; *) return 0 ;; esac
	if ! wd_lock "$WD_LOCK" "$LOCK_WAIT"; then
		log "автопереключение подписки отложено: watchdog занят"
		return 0
	fi
	deadline=$(($(now) + SWITCH_TIMEOUT - APPLY_MARGIN))
	res=$(ubus -t "$SWITCH_TIMEOUT" call "$CONFIG" subscription_autoswitch "{\"deadline\":$deadline}" 2>/dev/null) || res=""
	flat=$(echo "$res" | tr -d '\n\t')
	if [ -z "$flat" ]; then
		log "автопереключение подписки не выполнено: rpcd не ответил"
		return 1
	fi
	from=$(field switched_from "$flat")
	if [ -z "$from" ]; then
		case "$flat" in *'"error"'*) ;; *) return 0 ;; esac
		log "автопереключение подписки не выполнено: $(field error "$flat")"
		return 1
	fi
	msg="подписка $from $(field reason "$flat"): активной стала $(field active_sub "$flat")"
	case "$flat" in
		*'"error"'*)
			log "$msg, но применить конфиг не удалось"
			return 1
			;;
	esac
	log "$msg"
}

rc=0
count=0
while IFS= read -r id; do
	[ -n "$id" ] || continue
	count=$((count + 1))
	update_one "$id" || rc=1
done <<EOF
$(subscriptions)
EOF

[ "$count" -lt 2 ] || autoswitch || rc=1
exit "$rc"
