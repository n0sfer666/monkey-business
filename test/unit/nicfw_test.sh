#!/bin/sh
# Юнит-тест подмены прошивки NIC (root/usr/share/monkey-business/nicfw.sh). Гоняет РЕАЛЬНЫЙ скрипт
# по подставным путям (MB_NICFW_*), без root и без записи в системные каталоги.
# Главное, что защищаем: на чужом железе (нет r8152) скрипт НИЧЕГО не пишет в /lib/firmware,
# а pin в sysupgrade.conf не дублируется при повторных прогонах (деплой идемпотентен).
set -u

SELF_DIR=$(dirname "$0")
SCRIPT="$SELF_DIR/../../root/usr/share/monkey-business/nicfw.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

pass=0; fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "  FAIL: $1"; }
check() { if [ "$2" = "$3" ]; then ok; else bad "$1: ждали '$3', получили '$2'"; fi; }

SRC="$T/blob.fw"
DST="$T/fw/rtl_nic/rtl8153b-2.fw"
KEEP="$T/sysupgrade.conf"
printf 'rtl8153b-2 v1 10/23/19' >"$SRC"
: >"$KEEP"

# подставной /sys/class/net: eth1 -> драйвер задаётся симлинком
mkdir -p "$T/sys/eth1" "$T/drivers/r8152" "$T/drivers/other" "$T/dev/eth1"
ln -s "$T/dev/eth1" "$T/sys/eth1/device"
set_driver() { rm -f "$T/dev/eth1/driver"; ln -s "$T/drivers/$1" "$T/dev/eth1/driver"; }

run() {
	MB_NICFW_SRC="$SRC" MB_NICFW_DST="$DST" MB_NICFW_KEEP="$KEEP" MB_NICFW_SYSNET="$T/sys" \
		sh "$SCRIPT" "$1" 2>"$T/err"
}
installed() { if [ -f "$DST" ]; then cat "$DST"; else echo "<нет файла>"; fi; }
pins()      { grep -c "rtl8153b-2.fw" "$KEEP" 2>/dev/null || true; }

echo
echo "=== железо не наше (драйвер не r8152) -> НЕ трогаем /lib/firmware ==="
set_driver other
out="$(run apply)"; rc=$?
check "код возврата 0 (не ошибка)" "$rc" "0"
check "прошивка не установлена" "$(installed)" "<нет файла>"
check "sysupgrade.conf не тронут" "$(pins)" "0"
check "сказано, что пропускаем" "$(echo "$out" | grep -c 'пропускаем')" "1"
check "status: драйвера нет" "$(run status)" '{"driver_r8152":"no","v1_installed":"no","kept_on_sysupgrade":"no"}'

echo "=== наше железо, стоит чужая прошивка -> подменяем на v1 + пиним ==="
set_driver r8152
mkdir -p "$(dirname "$DST")"
printf 'rtl8153b-2 v2 04/27/23' >"$DST"
out="$(run apply)"
check "v1 установлена" "$(installed)" "rtl8153b-2 v1 10/23/19"
check "запинена в sysupgrade" "$(pins)" "1"
check "предупреждение про перезагрузку" "$(echo "$out" | grep -c 'перезагрузк')" "1"
check "status: всё на месте" "$(run status)" '{"driver_r8152":"yes","v1_installed":"yes","kept_on_sysupgrade":"yes"}'

echo "=== повторный apply -> no-op, pin НЕ дублируется ==="
out="$(run apply)"
check "сказано, что уже стоит" "$(echo "$out" | grep -c 'уже стоит')" "1"
check "pin по-прежнему один" "$(pins)" "1"
check "файл не изменился" "$(installed)" "rtl8153b-2 v1 10/23/19"

echo "=== прошивка на месте, но pin потерян (после sysupgrade) -> пин восстанавливается ==="
: >"$KEEP"
run apply >/dev/null
check "pin восстановлен" "$(pins)" "1"

echo "=== блоба нет -> ошибка, ничего не установлено ==="
rm -f "$SRC" "$DST"
rc=0
run apply >/dev/null || rc=$?
check "код возврата 1" "$rc" "1"
check "прошивка не установлена" "$(installed)" "<нет файла>"
check "ошибка про блоб" "$(grep -c 'нет блоба' "$T/err")" "1"

echo
echo "nicfw_test: $pass passed, $fail failed"
[ "$fail" = 0 ]
