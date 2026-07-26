#!/bin/sh
# Юнит-тест init-скрипта (root/etc/init.d/monkey-business). Сорсит его (dispatch живёт в
# rc.common, которого тут нет -> выполняются только определения) и подменяет procd-хелперы,
# uci, logger и sh мок-функциями. Пинит регрессию: reload_service ОБЯЗАН переобъявить
# procd-инстанс (procd_open_service ... procd_close_service), иначе procd не увидит новый хеш
# $CONF и xray продолжит крутить старый конфиг, а UI будет врать «Configuration applied».
# Переменные и функции читает сорснутый скрипт — SC2034/SC1090/SC2317 ложны.
# shellcheck disable=SC2034,SC1090,SC2317
set -u

SELF_DIR=$(dirname "$0")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

PASS=0; FAIL=0
has() { if grep -q "$3" "$2" 2>/dev/null; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL $1: '$3' missing in $2"; fi; }
no() { if grep -q "$3" "$2" 2>/dev/null; then FAIL=$((FAIL+1)); echo "FAIL $1: '$3' unexpected in $2"; else PASS=$((PASS+1)); fi; }

CALLS="$T/calls"

# rc_procd — копия обёртки из /etc/rc.common (снята с OpenWrt 25.12.1 / ImmortalWrt, ядро 6.12):
# именно она делает ubus-вызов set через procd_close_service, без неё procd не получает
# переобъявления вовсе. procd_lock (его берёт reload() в rc.common) здесь не воспроизводится —
# сериализация вызовов вне зоны этого теста.
rc_procd() {
	method="set"
	[ -n "${2:-}" ] && method="add"
	procd_open_service "monkey-business" "/etc/init.d/monkey-business"
	"$@"
	procd_close_service "$method"
}
procd_open_service() { echo "open_service $1" >> "$CALLS"; }
procd_close_service() { echo "close_service ${1:-}" >> "$CALLS"; }
procd_open_instance() { echo "open_instance" >> "$CALLS"; }
procd_close_instance() { echo "close_instance" >> "$CALLS"; }
procd_set_param() { echo "param $*" >> "$CALLS"; }
procd_add_reload_trigger() { echo "trigger $*" >> "$CALLS"; }
uci() { echo br-lan; }
logger() { cat >/dev/null; }
sh() { echo "sh $*" >> "$CALLS"; }

# shellcheck source=/dev/null
. "$SELF_DIR/../../root/etc/init.d/monkey-business"

# Пути из скрипта боевые (/etc/...) — переопределяем на temp, иначе start_service отвалится
# на `[ -f "$CONF" ]`, а flush/apply не отличить от реальных.
CONF="$T/xray.json"; : > "$CONF"
FW="$T/firewall"

# 1. reload_service переобъявляет инстанс через procd (иначе xray не перезапустится).
: > "$CALLS"
reload_service
has "reload.open_service" "$CALLS" "open_service monkey-business"
has "reload.close_set" "$CALLS" "close_service set"
has "reload.instance" "$CALLS" "open_instance"

# 2. Инстанс объявлен с боевой командой и с $CONF как файлом-триггером: по смене его хеша
#    procd бьёт процесс xray. Без param file перезапуска не будет никогда.
has "reload.command" "$CALLS" "param command /usr/bin/xray run -c $CONF"
has "reload.file" "$CALLS" "param file $CONF"
has "reload.respawn" "$CALLS" "param respawn"

# 3. reload НЕ трогает kill-switch: flush.sh не зовётся (это и есть причина, по которой
#    reload_service вообще определён — иначе rc.common подменил бы reload на restart).
no "reload.no_flush" "$CALLS" "flush.sh"
has "reload.apply_fw" "$CALLS" "sh $FW/apply.sh"

# 4. stop_service снимает правила (обратная сторона: его зовёт только реальный stop).
: > "$CALLS"
stop_service
has "stop.flush" "$CALLS" "sh $FW/flush.sh"
no "stop.no_apply" "$CALLS" "apply.sh"

# 5. Нет конфига — сервис не объявляется (нечего запускать).
: > "$CALLS"
rm -f "$CONF"
start_service || true
no "noconf.no_instance" "$CALLS" "open_instance"

# 6. Нет конфига + reload: ubus-вызова set быть НЕ должно. Без guard'а rc_procd отправил бы
#    set с пустыми instances -> procd снёс бы инстанс и убил живой xray, а kill-switch остался
#    бы поднят (LAN заперт без туннеля). Проверено на железе: pid исчезал, instances=0.
: > "$CALLS"
reload_service || true
no "noconf.no_set" "$CALLS" "close_service"
no "noconf.no_open" "$CALLS" "open_service"

printf 'initd_test: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
