#!/bin/sh
# Загрузка rpcd-плагина в БОЕВОЙ раскладке. Это единственный файл проекта с АБСОЛЮТНЫМИ импортами
# (/usr/share/rpcd/ucode/lib/monkey-business/...), и до этого теста его не компилировало ничто:
# опечатка в пути или в имени экспорта всплыла бы только на устройстве, где rpcd просто не
# зарегистрирует ubus-объект — а это разом мёртвый дашборд И мёртвый failover (watchdog ходит
# через `ubus call monkey-business config_apply`).
#
# Раскладываем src/ туда, куда его кладёт packaging, подсовываем стаб uci (нативного модуля в
# тест-образе нет) и выполняем плагин. Сверяем таблицу методов: она же — контракт ACL.
set -u

SELF_DIR=$(dirname "$0")
ROOT="$SELF_DIR/../.."
LIB=/usr/share/rpcd/ucode/lib/monkey-business
EXPECT="check_exit,config_apply,geo_install,geo_status,geo_update,hysteria_install,hysteria_status,parse_uri,servers_list,servers_ping,service_toggle,set_mode,set_routing,status,subscription_update"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

PASS=0; FAIL=0
eq() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL $1: want[$3] got[$2]"; fi; }

# Вне контейнера в /usr/share писать нечем и незачем — тест пропускается, а не падает.
if ! mkdir -p "$LIB" 2>/dev/null; then
	echo "plugin_load_test: SKIP (нет доступа к $LIB, запускай через make test-unit)"
	exit 0
fi
cp -R "$ROOT/src/." "$LIB/"

cat > "$T/uci.uc" <<'EOF'
function cursor() {
	return {
		foreach: function() {}, get: function() {}, set: function() {},
		add: function() { return "cfg"; }, delete: function() {},
		commit: function() { return true; },
	};
}
export { cursor };
EOF

cat > "$T/run.uc" <<EOF
let plugin = loadfile("$ROOT/root/usr/share/rpcd/ucode/monkey-business.uc");
let obj = plugin();
print(join(",", sort(keys(obj["monkey-business"]))));
EOF

got=$(ucode -L "$T/*.uc" "$T/run.uc" 2>"$T/err")
if [ -s "$T/err" ]; then
	FAIL=$((FAIL+1))
	echo "FAIL plugin.load:"
	cat "$T/err"
fi
eq "plugin.methods" "$got" "$EXPECT"

# buildCtx собирается на каждый вызов метода: несуществующий импорт или опечатка в имени
# рантайм-функции падает именно тут, а не на этапе загрузки.
cat > "$T/call.uc" <<EOF
let plugin = loadfile("$ROOT/root/usr/share/rpcd/ucode/monkey-business.uc");
let m = plugin()["monkey-business"];
let r = m.servers_list.call({ args: {} });
print(type(r.servers));
EOF
got=$(ucode -L "$T/*.uc" "$T/call.uc" 2>"$T/err2")
if [ -s "$T/err2" ]; then
	FAIL=$((FAIL+1))
	echo "FAIL plugin.dispatch:"
	cat "$T/err2"
fi
eq "plugin.servers_list" "$got" "array"

echo "plugin_load_test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
