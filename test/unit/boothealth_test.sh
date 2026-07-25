#!/bin/sh
# Юнит-тест boothealth (root/usr/share/monkey-business/boothealth.sh).
# Сорсит скрипт с BH_SOURCED=1 (dispatch не запускается) и подменяет побочные эффекты
# (mount/sync/stat/date) мок-функциями. Проверяет детект unclean/ro и логирование. Без root/сети.
# Переменные используются сорснутым скриптом — SC2034/SC1090 ложны.
# shellcheck disable=SC2034,SC1090
set -u

SELF_DIR=$(dirname "$0")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

BH_SOURCED=1
# shellcheck source=/dev/null
. "$SELF_DIR/../../root/usr/share/monkey-business/boothealth.sh"

MARKER="$T/marker"

# моки побочных эффектов
now() { echo "${BH_NOW:-1000}"; }
log_event() { echo "$1" >> "$T/log"; }
sync() { echo s >> "$T/sync"; }
root_ro() { [ -f "$T/ro" ]; }
remount_rw() { [ -f "$T/remount_ok" ] && rm -f "$T/ro"; }
read_state() { cat "$MARKER" 2>/dev/null || echo ''; }
write_state() { printf '%s\n' "$1" > "$MARKER"; }
marker_mtime() { cat "$T/mtime" 2>/dev/null || echo ''; }

reset() { rm -rf "$T"; mkdir -p "$T"; }

PASS=0; FAIL=0
eq() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL $1: want[$3] got[$2]"; fi; }
has() { if grep -q "$3" "$2" 2>/dev/null; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL $1: '$3' missing in $2"; fi; }
no() { if grep -q "$3" "$2" 2>/dev/null; then FAIL=$((FAIL+1)); echo "FAIL $1: '$3' unexpected"; else PASS=$((PASS+1)); fi; }
absent() { if [ -f "$2" ]; then FAIL=$((FAIL+1)); echo "FAIL $1: $2 exists"; else PASS=$((PASS+1)); fi; }

# 1. чистая загрузка: прошлый стоп был clean -> без инцидента, маркер -> running.
reset; write_state clean
boot
eq "clean.state" "$(read_state)" running
absent "clean.nolog" "$T/log"

# 2. грязная загрузка: маркер остался running -> лог unclean + время последней живости.
reset; write_state running; echo 950 > "$T/mtime"
boot
eq "unclean.state" "$(read_state)" running
has "unclean.log" "$T/log" "unclean shutdown"
has "unclean.mtime" "$T/log" "950"

# 3. первая загрузка: маркера нет -> не паниковать (без инцидента), маркер -> running.
reset
boot
eq "first.state" "$(read_state)" running
absent "first.nolog" "$T/log"

# 4. root смонтирован ro, remount удался -> лог + remounted rw=yes, дальше работает.
reset; write_state clean; : > "$T/ro"; : > "$T/remount_ok"
boot
has "ro_soft.log" "$T/log" "read-only at boot"
has "ro_soft.rw_yes" "$T/log" "remounted rw=yes"
eq "ro_soft.state" "$(read_state)" running

# 5. root ro, remount НЕ удался -> remounted rw=no (но не падаем).
reset; write_state clean; : > "$T/ro"
boot
has "ro_hard.rw_no" "$T/log" "remounted rw=no"

# 6. clean (стоп сервиса): маркер -> clean, единственный за цикл питания sync вызван.
reset; write_state running
clean
eq "clean_cmd.state" "$(read_state)" clean
has "clean_cmd.sync" "$T/sync" s

# 7. boot НЕ синкает: за цикл питания ровно один sync (на стопе), иначе флеш выгорает.
reset; write_state clean
boot
absent "boot.nosync" "$T/sync"

# 8. периодического heartbeat больше нет — `beat` должен быть неизвестной подкомандой.
reset
out=$(main beat 2>&1); rc=$?
eq "nobeat.rc" "$rc" 2
eq "nobeat.usage" "$(echo "$out" | grep -c 'boot|clean')" 1

# 9. жизненный цикл: clean -> boot(running) -> ребут без stop -> boot видит running -> unclean.
reset; write_state clean; boot; echo 980 > "$T/mtime"
boot
has "lifecycle.unclean" "$T/log" "unclean shutdown"

printf '\nboothealth_test: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
