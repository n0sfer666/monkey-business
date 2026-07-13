#!/bin/sh
# Юнит-тест NIC-watchdog (root/usr/share/monkey-business/nicwatch.sh). Гоняет РЕАЛЬНЫЙ скрипт
# по подставному /sys (MB_NIC_*), с моками ip/logger/sleep через PATH. Сеть/root не нужны.
# Главная защищаемая инварианта: пока идёт трафик (tx_packets растёт), линк не трогаем,
# сколько бы ни росли tx_errors — иначе watcher сам роняет живой LAN.
set -u

SELF_DIR=$(dirname "$0")
SCRIPT="$SELF_DIR/../../root/usr/share/monkey-business/nicwatch.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

pass=0; fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "  FAIL: $1"; }
check() { if [ "$2" = "$3" ]; then ok; else bad "$1: ждали '$3', получили '$2'"; fi; }

mkdir -p "$T/bin" "$T/sys/eth1/statistics" "$T/usbdrv" "$T/usbdev/2-1:1.0"
ln -s "$T/usbdev/2-1:1.0" "$T/sys/eth1/device"

cat >"$T/bin/ip" <<EOF
#!/bin/sh
echo "\$*" >> "$T/ip.log"
EOF
cat >"$T/bin/logger" <<EOF
#!/bin/sh
echo "\$*" >> "$T/logger.log"
EOF
# sleep-мок заодно моделирует «устройство вернулось после bind»: bind_dev пишет в usbdrv/bind,
# ждёт и проверяет netdev — флагом bind_heals управляем, оживёт интерфейс или нет
cat >"$T/bin/sleep" <<EOF
#!/bin/sh
[ -f "$T/bind_heals" ] && mkdir -p "$T/sys/eth1/statistics"
exit 0
EOF
chmod +x "$T/bin/ip" "$T/bin/logger" "$T/bin/sleep"

set_counters() { printf '%s\n' "$1" >"$T/sys/eth1/statistics/tx_errors"
                 printf '%s\n' "$2" >"$T/sys/eth1/statistics/tx_packets"; }

run() {
	PATH="$T/bin:$PATH" MB_NIC_IFACE=eth1 MB_NIC_STATE_DIR="$T/state" \
		MB_NIC_SYSNET="$T/sys" MB_NIC_USBDRV="$T/usbdrv" sh "$SCRIPT"
}

reset_logs() { rm -f "$T/ip.log" "$T/logger.log" "$T/usbdrv/unbind" "$T/usbdrv/bind"; }
ip_calls()   { if [ -f "$T/ip.log" ]; then wc -l < "$T/ip.log" | tr -d ' '; fi; }
rebound()    { if [ -f "$T/usbdrv/bind" ]; then echo yes; else echo no; fi; }

echo
echo "=== nicwatch: первый прогон — только базлайн, без действий ==="
set_counters 10 1000
run
check "первый тик: ip не звался" "$(ip_calls)" ""
check "состояние записано" "$(cat "$T/state/state")" "10 1000 0"

echo "=== трафик идёт: tx_errors растёт, но и tx_packets тоже -> НЕ трогать линк ==="
reset_logs
set_counters 25 1500
run
check "живой трафик: ip не звался" "$(ip_calls)" ""
check "страйки не копятся" "$(cat "$T/state/state")" "25 1500 0"

echo "=== залипание: tx_errors растёт, tx_packets стоит -> bounce линка (страйк 1) ==="
reset_logs
set_counters 26 1500
run
check "страйк 1: два вызова ip (down+up)" "$(ip_calls)" "2"
check "  ip down" "$(sed -n 1p "$T/ip.log")" "link set eth1 down"
check "  ip up"   "$(sed -n 2p "$T/ip.log")" "link set eth1 up"
check "USB не трогали" "$(rebound)" "no"
check "страйк записан" "$(cat "$T/state/state")" "26 1500 1"

echo "=== залипание повторно -> эскалация в USB re-bind (страйк 2) ==="
reset_logs
set_counters 27 1500
run
check "страйк 2: USB re-bind" "$(rebound)" "yes"
check "  unbind получил имя устройства" "$(cat "$T/usbdrv/unbind")" "2-1:1.0"
check "  bind получил имя устройства"   "$(cat "$T/usbdrv/bind")"   "2-1:1.0"
check "линк не дёргали" "$(ip_calls)" ""
check "страйк записан" "$(cat "$T/state/state")" "27 1500 2"

echo "=== счётчики обнулились (re-probe драйвера) -> базлайн, без действий ==="
reset_logs
set_counters 0 0
run
check "сброс: ip не звался" "$(ip_calls)" ""
check "сброс: USB не трогали" "$(rebound)" "no"
check "страйки сброшены" "$(cat "$T/state/state")" "0 0 0"

echo "=== ошибок нет, пакетов нет (тишина в сети) -> без действий ==="
reset_logs
set_counters 0 0
run
check "тишина: ip не звался" "$(ip_calls)" ""
check "состояние стабильно" "$(cat "$T/state/state")" "0 0 0"

echo "=== выздоровление: после страйка трафик пошёл -> страйки обнуляются ==="
reset_logs
set_counters 5 0
run
check "страйк 1 после залипания" "$(cat "$T/state/state")" "5 0 1"
reset_logs
set_counters 5 50
run
check "трафик пошёл: страйки сброшены" "$(cat "$T/state/state")" "5 50 0"
check "выздоровление: ip не звался" "$(ip_calls)" ""

echo "=== нет интерфейса -> тихий выход 0 ==="
reset_logs
rc=0
PATH="$T/bin:$PATH" MB_NIC_IFACE=nosuch MB_NIC_STATE_DIR="$T/state" \
	MB_NIC_SYSNET="$T/sys" MB_NIC_USBDRV="$T/usbdrv" sh "$SCRIPT" || rc=$?
check "код возврата 0" "$rc" "0"
check "ip не звался" "$(ip_calls)" ""

echo "=== интерфейс пропал после нашего unbind, bind не помог -> НЕ молчим, пробуем снова ==="
reset_logs
rm -rf "$T/sys/eth1"
printf '2-1:1.0' >"$T/state/usbdev.eth1"
rc=0
run || rc=$?
check "код возврата 0" "$rc" "0"
check "bind был вызван повторно" "$(rebound)" "yes"
check "маркер отвязки сохранён (пробуем на след. тике)" \
	"$(if [ -f "$T/state/usbdev.eth1" ]; then echo есть; else echo нет; fi)" "есть"
check "провал залогирован" "$(grep -c 'не помог' "$T/logger.log")" "1"

echo "=== ...и когда устройство наконец возвращается -> маркер снят, LAN восстановлена ==="
reset_logs
: >"$T/bind_heals"
run
check "интерфейс восстановлен" "$(if [ -d "$T/sys/eth1" ]; then echo yes; else echo no; fi)" "yes"
check "маркер отвязки снят" "$(if [ -f "$T/state/usbdev.eth1" ]; then echo есть; else echo нет; fi)" "нет"
check "восстановление залогировано" "$(grep -c 'вернулся' "$T/logger.log")" "1"
rm -f "$T/bind_heals"
# re-probe пересоздаёт и симлинк на USB-устройство — вернуть, иначе rebind_usb ниже нечего дёргать
ln -sf "$T/usbdev/2-1:1.0" "$T/sys/eth1/device"
set_counters 0 0

echo "=== устойчивое залипание -> re-bind не каждую минуту (потолок + пауза) ==="
reset_logs
printf '100 500 5\n' >"$T/state/state"
set_counters 101 500
run
check "страйк 6: re-bind пропущен (пауза)" "$(rebound)" "no"
check "линк не дёргали" "$(ip_calls)" ""
check "пауза залогирована" "$(grep -c 'пауза' "$T/logger.log")" "1"
reset_logs
printf '100 500 9\n' >"$T/state/state"
set_counters 101 500
run
check "страйк 10: попытка возобновлена" "$(rebound)" "yes"

echo
echo "nicwatch_test: $pass passed, $fail failed"
[ "$fail" = 0 ]
