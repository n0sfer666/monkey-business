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
# переобъявления вовсе. procd_lock не мокается: настоящий берётся уже при сорсинге procd.sh
# (_procd_wrapper), т.е. сериализация вызовов init-скрипта существует до и независимо от этого кода.
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
# MB_ENABLED=missing — опции в конфиге нет: uci выходит с ошибкой и НЕ печатает ничего (так ведёт
# себя `uci -q get` на отсутствующей опции), т.е. дефолт mb_intent реально проверяется.
MB_ENABLED=1
uci() {
	case "$*" in
		*.enabled) [ "$MB_ENABLED" = missing ] && return 1; echo "$MB_ENABLED";;
		*) echo br-lan;;
	esac
}
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

# 7. Тумблер выключен: инстанс не объявляется (START=95 иначе поднимал туннель на загрузке
#    независимо от выбора пользователя), tproxy не применяется, а правила СНИМАЮТСЯ — иначе `start`
#    при живом xray отдал бы procd пустые instances (процесс умрёт), а kill-switch остался бы
#    поднят: LAN заперт без туннеля.
: > "$CALLS"
: > "$CONF"
MB_ENABLED=0
start_service || true
no "off.no_instance" "$CALLS" "open_instance"
no "off.no_apply" "$CALLS" "$FW/apply.sh"
has "off.flush" "$CALLS" "sh $FW/flush.sh"

# 8. Тумблер выключен + reload: выход ДО rc_procd. Иначе ушёл бы set с пустыми instances -> procd
#    снёс бы ЖИВОЙ xray, а flush.sh не вызывается и kill-switch остался бы поднят (LAN заперт).
#    Правила reload при этом НЕ снимает: снятие — дело stop, а reload при живом туннеле не должен
#    ронять kill-switch (это разница с кейсом 7, где start иначе убил бы xray, оставив правила).
: > "$CALLS"
reload_service || true
no "off.no_set" "$CALLS" "close_service"
no "off.no_open" "$CALLS" "open_service"
no "off.no_flush" "$CALLS" "flush.sh"

# 9. Тумблер включён обратно — сервис снова объявляется (гейт не залипает).
: > "$CALLS"
MB_ENABLED=1
reload_service
has "on.instance" "$CALLS" "open_instance"
has "on.close_set" "$CALLS" "close_service set"

# 10. Опции enabled в конфиге нет (обрезанный/старый конфиг): дефолт = ВЫКЛ — тот же, что у watchdog
#     (read_intent) и rpcd (isTrue(undefined)). Дефолт «вкл» давал туннель, про который UI пишет off,
#     а watchdog за ним не следит: умри xray — LAN заперт kill-switch'ем без самолечения.
: > "$CALLS"
MB_ENABLED=missing
start_service || true
no "nodefault.no_instance" "$CALLS" "open_instance"
has "nodefault.flush" "$CALLS" "sh $FW/flush.sh"
: > "$CALLS"
reload_service || true
no "nodefault.no_set" "$CALLS" "close_service"

# 11. MB_INTENT=1 обходит гейт: путь включения (service_toggle) поднимает туннель ДО commit'а
#     тумблера, иначе enabled=1 висел бы всё время пробы серверов и cron-watchdog успевал поднять
#     СТАРЫЙ конфиг себе под ноги.
: > "$CALLS"
MB_ENABLED=0
MB_INTENT=1
reload_service
unset MB_INTENT
has "intent.instance" "$CALLS" "open_instance"
has "intent.close_set" "$CALLS" "close_service set"
no "intent.no_flush" "$CALLS" "flush.sh"

# 12. Префикс MB_INTENT сшивается строкой в рантайме rpcd, и опечатка в ней (потерянный хвостовой
#     пробел, `MB_INTENT =1`) молча ломала бы КАЖДОЕ включение при enabled=0: моки такого не видят,
#     потому что читают переменную, а не команду. Пиним обе половины склейки.
RT="$SELF_DIR/../../root/usr/share/rpcd/ucode/monkey-business.uc"
has "intent.runtime_prefix" "$RT" "intentOn ? 'MB_INTENT=1 ' : ''"
has "intent.runtime_cmd" "$RT" "+ '/etc/init.d/monkey-business reload"

printf 'initd_test: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
