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
# MB_SUB_MIN(300) MB_SUB_UBUS_TIMEOUT(60) MB_SUB_NOW(epoch).
set -u

CONFIG=monkey-business
STATE_DIR="${MB_SUB_STATE_DIR:-/tmp/mb-subupdate}"
STATE="$STATE_DIR/last"
# Пауза после неудачи: панель недоступна (нет сети, VPN лежит) — это норма, но долбиться к ней
# каждую минуту нельзя.
RETRY="${MB_SUB_RETRY:-900}"
# Нижняя граница интервала: опечатка в поле формы (10 вместо 86400) не должна превращаться
# в обстрел панели.
MIN="${MB_SUB_MIN:-300}"
UBUS_TIMEOUT="${MB_SUB_UBUS_TIMEOUT:-60}"
NOW="${MB_SUB_NOW:-$(date +%s)}"

log() { logger -t mb-subupdate "$@" 2>/dev/null || true; }
cfg() { uci -q get "$CONFIG.subscription.$1" 2>/dev/null || echo ""; }
# нечисло -> дефолт: пустой или битый uci не должен ронять арифметику, иначе скрипт молча
# умирал бы на каждом тике
num() { case "${1:-}" in '' | *[!0-9]*) echo "$2" ;; *) echo "$1" ;; esac; }
# Логируем только числа и фиксированные строки ошибок: errors[] из парсера содержит обрезанные
# строки подписки, а в них uuid/пароли — в syslog им не место.
field() { echo "$2" | sed -n "s/.*\"$1\"[ 	]*:[ 	]*\"\{0,1\}\([^\",}]*\).*/\1/p"; }

[ "$(cfg auto_update)" = 1 ] || exit 0
[ -n "$(cfg url)" ] || exit 0

interval=$(num "$(cfg update_interval)" 86400)
[ "$interval" -ge "$MIN" ] || interval="$MIN"

last=0
result=""
read -r last result 2>/dev/null <"$STATE" || true
last=$(num "${last:-0}" 0)
result="${result:-}"
# часы прыгнули назад (NTP выставил время после загрузки из 1970) -> считаем, что пора
[ "$NOW" -ge "$last" ] || last=0

due="$interval"
[ "$result" = ok ] || due="$RETRY"
[ "$last" -eq 0 ] || [ $((NOW - last)) -ge "$due" ] || exit 0

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
# Штамп ДО вызова: тик занимает до UBUS_TIMEOUT секунд, а cron придёт через минуту — без этого
# следующий тик начал бы второе обновление поверх незакончившегося первого.
printf '%s run\n' "$NOW" >"$STATE"

res=$(ubus -t "$UBUS_TIMEOUT" call "$CONFIG" subscription_update '{}' 2>/dev/null) || res=""
flat=$(echo "$res" | tr -d '\n\t')

if [ -z "$flat" ]; then
	printf '%s fail\n' "$NOW" >"$STATE"
	log "подписка не обновлена: rpcd не ответил"
	exit 1
fi

case "$flat" in
	*'"error"'*)
		printf '%s fail\n' "$NOW" >"$STATE"
		log "подписка не обновлена: $(field error "$flat")"
		exit 1
		;;
esac

printf '%s ok\n' "$NOW" >"$STATE"
log "подписка обновлена: серверов $(field added "$flat")"
