#!/bin/sh
# Юнит-тест автообновления подписки (root/usr/share/monkey-business/subupdate.sh). Гоняет РЕАЛЬНЫЙ
# скрипт с моками uci/ubus/logger через PATH и подставным временем (MB_SUB_NOW). Сеть/root не нужны.
# Главные защищаемые инварианты: выключенный тумблер не обновляет НИЧЕГО, между обновлениями
# выдерживается интервал (а после неудачи — пауза RETRY), и в syslog не утекают данные серверов.
set -u

SELF_DIR=$(dirname "$0")
SCRIPT="$SELF_DIR/../../root/usr/share/monkey-business/subupdate.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

PASS=0; FAIL=0
eq() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "  FAIL $1: ждали '$3', получили '$2'"; fi; }

mkdir -p "$T/bin" "$T/uci"

cat >"$T/bin/uci" <<EOF
#!/bin/sh
f="$T/uci/\${3##*.}"
[ -s "\$f" ] || exit 1
cat "\$f"
EOF
cat >"$T/bin/ubus" <<EOF
#!/bin/sh
echo "\$*" >> "$T/ubus.log"
cat "$T/ubus.out" 2>/dev/null
exit "\$(cat "$T/ubus.rc" 2>/dev/null || echo 0)"
EOF
cat >"$T/bin/logger" <<EOF
#!/bin/sh
shift 2
echo "\$*" >> "$T/logger.log"
EOF
chmod +x "$T/bin/uci" "$T/bin/ubus" "$T/bin/logger"

set_cfg() { printf '%s' "$2" > "$T/uci/$1"; }
set_resp() { printf '%s' "$1" > "$T/ubus.out"; printf '%s' "${2:-0}" > "$T/ubus.rc"; }
calls() { wc -l < "$T/ubus.log" 2>/dev/null | tr -d ' '; }
reset() { : > "$T/ubus.log"; : > "$T/logger.log"; rm -rf "$T/state"; }

# NOW передаём явно: тик гейтится по времени, и без управляемых часов тест проверял бы только удачу
run() {
	PATH="$T/bin:$PATH" MB_SUB_STATE_DIR="$T/state" MB_SUB_NOW="$1" sh "$SCRIPT" >/dev/null 2>&1
}

set_cfg url 'https://panel.example/sub/token'
set_cfg auto_update 1
set_cfg update_interval 3600
set_resp '{ "format": "vpnon", "added": 7, "errors": [ ] }'

# 1. тумблер выключен -> ubus не зовём вовсе
reset
set_cfg auto_update 0
run 1000
eq "off.calls" "$(calls)" "0"

# 2. тумблер включён, но URL пуст -> обновлять нечего
reset
set_cfg auto_update 1
set_cfg url ''
run 1000
eq "nourl.calls" "$(calls)" "0"

# 3. первый запуск (состояния нет) -> обновляемся сразу, штамп ok
reset
set_cfg url 'https://panel.example/sub/token'
run 1000
eq "first.calls" "$(calls)" "1"
eq "first.state" "$(cat "$T/state/last")" "1000 ok"
eq "first.log" "$(cat "$T/logger.log")" "подписка обновлена: серверов 7"

# 4. интервал не вышел -> второго обновления нет
run 4599
eq "early.calls" "$(calls)" "1"

# 5. интервал вышел -> обновляемся снова
run 4600
eq "due.calls" "$(calls)" "2"
eq "due.state" "$(cat "$T/state/last")" "4600 ok"

# 6. интервал ниже MIN подтягивается до 300: через минуту ещё рано, через 300с — пора
reset
set_cfg update_interval 10
run 1000
run 1060
eq "clamp.early" "$(calls)" "1"
run 1300
eq "clamp.due" "$(calls)" "2"

# 7. ошибка от rpcd -> штамп fail и пауза RETRY(900), а не interval(3600)
reset
set_cfg update_interval 3600
set_resp '{ "error": "fetch failed", "kept": 7 }'
run 1000
eq "err.state" "$(cat "$T/state/last")" "1000 fail"
run 1800
eq "err.early" "$(calls)" "1"
run 1900
eq "err.retry" "$(calls)" "2"

# 8. rpcd не ответил (ubus упал) -> тоже fail, без обращения к несуществующему ответу
reset
set_resp '' 1
run 1000
eq "dead.state" "$(cat "$T/state/last")" "1000 fail"
eq "dead.log" "$(cat "$T/logger.log")" "подписка не обновлена: rpcd не ответил"

# 9. в syslog уходит только текст ошибки: errors[] содержит куски ссылок с uuid/паролями
reset
set_resp '{ "error": "no servers parsed", "errors": [ "unparseable: vless://11111111-2222-3333@h:443" ] }'
run 1000
eq "secret.log" "$(cat "$T/logger.log")" "подписка не обновлена: no servers parsed"

# 10. часы прыгнули назад (NTP после загрузки) -> не залипаем до конца эпохи
reset
set_resp '{ "format": "vpnon", "added": 7, "errors": [ ] }'
run 9000
run 100
eq "clockback.calls" "$(calls)" "2"

printf 'subupdate_test: %d ok, %d fail\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
