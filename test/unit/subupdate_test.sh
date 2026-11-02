#!/bin/sh
# Юнит-тест автообновления подписок (root/usr/share/monkey-business/subupdate.sh). Гоняет РЕАЛЬНЫЙ
# скрипт с моками uci/ubus/logger через PATH и подставным временем (MB_SUB_NOW). Сеть/root не нужны.
# Главные защищаемые инварианты: выключенный тумблер не обновляет НИЧЕГО, между обновлениями
# выдерживается интервал (а после неудачи — пауза RETRY), и в syslog не утекают данные серверов.
set -u

SELF_DIR=$(dirname "$0")
SCRIPT="$SELF_DIR/../../root/usr/share/monkey-business/subupdate.sh"
T=$(mktemp -d)
HOLDER=""
trap '[ -z "$HOLDER" ] || kill "$HOLDER" 2>/dev/null; rm -rf "$T"' EXIT

PASS=0; FAIL=0
eq() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "  FAIL $1: ждали '$3', получили '$2'"; fi; }

mkdir -p "$T/bin" "$T/uci" "$T/resp" "$T/wd"

cat >"$T/bin/uci" <<EOF
#!/bin/sh
if [ "\$2" = -X ] && [ "\$3" = show ]; then
	echo "monkey-business.global=global"
	while IFS= read -r id; do echo "monkey-business.\$id=subscription"; done < "$T/uci/_subs"
	echo "monkey-business.cfg01=server"
	exit 0
fi
if [ "\$2" = show ]; then
	n=0
	while IFS= read -r id; do echo "monkey-business.@subscription[\$n]=subscription"; n=\$((n + 1)); done < "$T/uci/_subs"
	exit 0
fi
key=\${3#*.}
f="$T/uci/\$key"
[ -s "\$f" ] || exit 1
cat "\$f"
EOF
cat >"$T/bin/ubus" <<EOF
#!/bin/sh
shift 3
echo "\$2 \$3" >> "$T/ubus.log"
sub=\$(echo "\$3" | sed -n 's/.*"sub":"\([^"]*\)".*/\1/p')
key="\$2"
[ -z "\$sub" ] || key="\$2.\$sub"
[ "\$2" != subscription_autoswitch ] || case "\$3" in *check*) key="\$2.check" ;; esac
[ -e "$T/resp/\$key" ] || key="\$2"
cat "$T/resp/\$key" 2>/dev/null
exit "\$(cat "$T/resp/\$key.rc" 2>/dev/null || echo 0)"
EOF
cat >"$T/bin/logger" <<EOF
#!/bin/sh
shift 2
echo "\$*" >> "$T/logger.log"
EOF
chmod +x "$T/bin/uci" "$T/bin/ubus" "$T/bin/logger"

subs() { printf '%s\n' "$@" > "$T/uci/_subs"; }
set_cfg() { printf '%s' "$3" > "$T/uci/$1.$2"; }
set_resp() { printf '%s' "$2" > "$T/resp/$1"; printf '%s' "${3:-0}" > "$T/resp/$1.rc"; }
calls() { grep -c "${1:-.}" "$T/ubus.log" 2>/dev/null; true; }
reset() { : > "$T/ubus.log"; : > "$T/logger.log"; rm -rf "$T/state"; }

# NOW передаём явно: тик гейтится по времени, и без управляемых часов тест проверял бы только удачу
run() {
	PATH="$T/bin:$PATH" MB_SUB_STATE_DIR="$T/state" MB_SUB_NOW="$1" MB_SUB_WD_LOCK="$T/wd/lock" \
		MB_SUB_LOCK_WAIT=1 sh "$SCRIPT" >/dev/null 2>&1
}

subs subscription
set_cfg subscription url 'https://panel.example/sub/token'
set_cfg subscription auto_update 1
set_cfg subscription update_interval 3600
set_resp subscription_update '{ "format": "vpnon", "added": 7, "errors": [ ] }'
set_resp subscription_autoswitch '{ "ok": true, "active_sub": "subscription" }'

# 1. тумблер выключен -> ubus не зовём вовсе
reset
set_cfg subscription auto_update 0
run 1000
eq "off.calls" "$(calls)" "0"

# 2. тумблер включён, но URL пуст -> обновлять нечего
reset
set_cfg subscription auto_update 1
set_cfg subscription url ''
run 1000
eq "nourl.calls" "$(calls)" "0"

# 3. первый запуск (состояния нет) -> обновляемся сразу, штамп ok, id подписки уходит в rpcd
reset
set_cfg subscription url 'https://panel.example/sub/token'
run 1000
eq "first.calls" "$(calls)" "1"
eq "first.arg" "$(cat "$T/ubus.log")" 'subscription_update {"sub":"subscription"}'
eq "first.state" "$(cat "$T/state/subscription")" "1000 ok"
eq "first.log" "$(cat "$T/logger.log")" "подписка subscription обновлена: серверов 7"

# 4. интервал не вышел -> второго обновления нет
run 4599
eq "early.calls" "$(calls)" "1"

# 5. интервал вышел -> обновляемся снова
run 4600
eq "due.calls" "$(calls)" "2"
eq "due.state" "$(cat "$T/state/subscription")" "4600 ok"

# 6. интервал ниже MIN подтягивается до 600: через 300с ещё рано, через 600с — пора
reset
set_cfg subscription update_interval 10
run 1000
run 1300
eq "clamp.early" "$(calls)" "1"
run 1600
eq "clamp.due" "$(calls)" "2"

# 6a. интервал выше MAX (старые сутки) срезается до 7200
reset
set_cfg subscription update_interval 86400
run 1000
run 8100
eq "clamp.max.early" "$(calls)" "1"
run 8200
eq "clamp.max.due" "$(calls)" "2"

# 6b. пустой или битый интервал -> час
reset
set_cfg subscription update_interval ''
run 1000
run 4500
eq "default.early" "$(calls)" "1"
run 4600
eq "default.due" "$(calls)" "2"

# 7. ошибка от rpcd -> штамп fail и пауза RETRY(900), а не interval(3600)
reset
set_cfg subscription update_interval 3600
set_resp subscription_update '{ "error": "fetch failed", "kept": 7 }'
run 1000
eq "err.state" "$(cat "$T/state/subscription")" "1000 fail"
run 1800
eq "err.early" "$(calls)" "1"
run 1900
eq "err.retry" "$(calls)" "2"

# 8. rpcd не ответил (ubus упал) -> тоже fail, без обращения к несуществующему ответу
reset
set_resp subscription_update '' 1
run 1000
eq "dead.state" "$(cat "$T/state/subscription")" "1000 fail"
eq "dead.log" "$(cat "$T/logger.log")" "подписка subscription не обновлена: rpcd не ответил"

# 9. в syslog уходит только текст ошибки: errors[] содержит куски ссылок с uuid/паролями
reset
set_resp subscription_update '{ "error": "no servers parsed", "errors": [ "unparseable: vless://11111111-2222-3333@h:443" ] }'
run 1000
eq "secret.log" "$(cat "$T/logger.log")" "подписка subscription не обновлена: no servers parsed"

# 10. часы прыгнули назад (NTP после загрузки) -> не залипаем до конца эпохи
reset
set_resp subscription_update '{ "format": "vpnon", "added": 7, "errors": [ ] }'
run 9000
run 100
eq "clockback.calls" "$(calls)" "2"

# 11. одна подписка -> переключаться не на что, rpc автопереключения не зовём
eq "single.noswitch" "$(calls subscription_autoswitch)" "0"

# 12. две подписки: у каждой свой тумблер и своё состояние, провал одной не блокирует другую
reset
subs subscription sub_b sub_c
set_cfg sub_b url 'https://b.example/sub'
set_cfg sub_b auto_update 1
set_cfg sub_b update_interval 7200
set_cfg sub_c url 'https://c.example/sub'
set_cfg sub_c auto_update 0
set_resp subscription_update.subscription '{ "error": "fetch failed" }'
set_resp subscription_update.sub_b '{ "added": 3 }'
run 1000
eq "multi.legacy" "$(cat "$T/state/subscription")" "1000 fail"
eq "multi.b" "$(cat "$T/state/sub_b")" "1000 ok"
eq "multi.c" "$(calls sub_c)" "0"
eq "multi.blog" "$(grep -c 'подписка sub_b обновлена: серверов 3' "$T/logger.log")" "1"
set_resp subscription_update.subscription '{ "added": 7 }'
run 2000
eq "multi.retry_only_failed" "$(calls subscription_update)" "3"
eq "multi.legacy.retry" "$(cat "$T/state/subscription")" "2000 ok"
eq "multi.b.kept" "$(cat "$T/state/sub_b")" "1000 ok"

# 13. автопереключение идёт на каждом тике, даже когда обновлять нечего; без switch_to — только проверка
reset
set_cfg subscription auto_update 0
set_cfg sub_b auto_update 0
run 1000
eq "check.calls" "$(calls)" "1"
eq "check.arg" "$(cat "$T/ubus.log")" 'subscription_autoswitch {"check":true}'

# 14. проверка нашла мёртвую активную -> под локом watchdog второй вызов с дедлайном
reset
set_resp subscription_autoswitch.check '{ "ok": true, "active_sub": "subscription", "dead": "exhausted", "switch_to": "sub_b" }'
set_resp subscription_autoswitch '{ "ok": true, "active_sub": "sub_b", "switched_from": "subscription", "reason": "exhausted", "applied": true }'
run 1000
eq "switch.calls" "$(calls subscription_autoswitch)" "2"
eq "switch.deadline" "$(tail -n 1 "$T/ubus.log")" 'subscription_autoswitch {"deadline":1075}'
eq "switch.log" "$(cat "$T/logger.log")" "подписка subscription exhausted: активной стала sub_b"

# 15. apply после переключения не прошёл -> в логе это видно, детали ошибки не утекают
reset
set_resp subscription_autoswitch '{ "ok": false, "error": "xray -test failed", "active_sub": "sub_b", "switched_from": "subscription", "reason": "expired" }'
run 1000
eq "applyfail.log" "$(cat "$T/logger.log")" "подписка subscription expired: активной стала sub_b, но применить конфиг не удалось"

# 16. watchdog держит лок -> переключение откладывается, второго вызова нет
reset
if command -v flock >/dev/null 2>&1; then
	( exec 9>"$T/wd/lock"; flock -n 9 && exec sleep 30 ) &
	HOLDER=$!
	sleep 1
else
	mkdir "$T/wd/lock.d"
fi
run 1000
eq "busy.calls" "$(calls subscription_autoswitch)" "1"
eq "busy.log" "$(cat "$T/logger.log")" "автопереключение подписки отложено: watchdog занят"
[ -z "$HOLDER" ] || { kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null; HOLDER=""; }
rmdir "$T/wd/lock.d" 2>/dev/null

# 17. лок освободился -> следующий тик переключает
reset
run 1060
eq "free.calls" "$(calls subscription_autoswitch)" "2"

# 18. между проверкой и локом переключили без нас -> штатно: без лога и rc=0
reset
set_resp subscription_autoswitch '{ "ok": true, "active_sub": "sub_b" }'
run 1000
eq "raced.rc" "$?" "0"
eq "raced.log" "$(cat "$T/logger.log")" ""

# 19. rpcd не ответил на переключение -> это сбой, и в логе он назван
reset
set_resp subscription_autoswitch '' 1
run 1000
eq "switchdead.rc" "$?" "1"
eq "switchdead.log" "$(cat "$T/logger.log")" "автопереключение подписки не выполнено: rpcd не ответил"

# 20. анонимная секция (uci add) видна под реальным именем, как её видит rpcd
reset
subs cfg0a1b2c
set_cfg cfg0a1b2c url 'https://anon.example/sub'
set_cfg cfg0a1b2c auto_update 1
set_cfg cfg0a1b2c update_interval 3600
run 1000
eq "anon.arg" "$(cat "$T/ubus.log")" 'subscription_update {"sub":"cfg0a1b2c"}'
eq "anon.state" "$(cat "$T/state/cfg0a1b2c")" "1000 ok"

printf 'subupdate_test: %d ok, %d fail\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
