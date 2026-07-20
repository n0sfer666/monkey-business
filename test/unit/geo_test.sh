#!/bin/sh
# Юнит-тест geo.sh cmd_download: перебор зеркал, превентивная проверка места, говорящие статусы.
# fetch.sh подменяется фейком (mb_fetch/mb_remote_size), xray/df/uci — стабами через PATH,
# состояние читаем из изолированного STATE-файла (MB_GEO_STATE). Реальная сеть/xray не нужны.
set -u

SELF_DIR=$(dirname "$0")
GEO="$SELF_DIR/../../root/usr/share/monkey-business/geo.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

pass=0; fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "  FAIL: $1"; }
check()    { if [ "$2" = "$3" ]; then ok; else bad "$1: ждали '$3', получили '$2'"; fi; }
contains() { case "$2" in *"$3"*) ok ;; *) bad "$1: в '$2' нет '$3'" ;; esac; }

mkdir -p "$T/bin" "$T/lib" "$T/dest"

# Фейк fetch.sh: .sha256sum всегда мимо (rsum пуст -> без checksum-ветки). Основной файл успешен,
# только если задан MB_TEST_OK и URL его содержит (симуляция «живого» зеркала); MB_TEST_FETCH_RC=1
# роняет все. Размер — из MB_TEST_SIZE (пусто = «не узнали»).
cat >"$T/lib/fetch.sh" <<'EOF'
mb_fetch() {
	case "$1" in *.sha256sum) return 1 ;; esac
	[ "${MB_TEST_FETCH_RC:-0}" = 0 ] || return 1
	if [ -n "${MB_TEST_OK:-}" ]; then case "$1" in *"$MB_TEST_OK"*) : ;; *) return 1 ;; esac; fi
	echo geodata > "$2"; return 0
}
mb_remote_size() { printf '%s' "${MB_TEST_SIZE:-}"; }
EOF

printf '#!/bin/sh\nexit 0\n' > "$T/bin/xray"
cat >"$T/bin/df" <<'EOF'
#!/bin/sh
echo "Filesystem 1K-blocks Used Available Use% Mounted"
echo "stub 1000000 0 ${MB_TEST_FREE_KB:-900000} 0% /"
EOF
printf '#!/bin/sh\nexit 1\n' > "$T/bin/uci"
chmod +x "$T/bin/xray" "$T/bin/df" "$T/bin/uci"

STATEF="$T/geo.state"; OUTF="$T/geo.out"
run() { # запуск download; печатает rc, состояние -> $STATEF, stdout -> $OUTF
	rm -f "$STATEF" "$OUTF"; rm -f "$T/dest"/*.dat 2>/dev/null
	rc=0
	env PATH="$T/bin:$PATH" MB_LIB_DIR="$T/lib" MB_GEO_DIR="$T/dest" \
		MB_GEO_STATE="$STATEF" TMPDIR="$T" "$@" \
		sh "$GEO" download >"$OUTF" 2>/dev/null || rc=$?
	echo "$rc"
}
state() { cat "$STATEF" 2>/dev/null || echo "<нет>"; }
out()   { cat "$OUTF" 2>/dev/null; }
dat_n() { find "$T/dest" -maxdepth 1 -name '*.dat' 2>/dev/null | wc -l | tr -d ' '; }

echo
echo "=== места не хватает (размер известен) -> ошибка no space ДО скачивания ==="
rc="$(run MB_TEST_SIZE=50000000 MB_TEST_FREE_KB=20000)"
check    "код возврата 1"       "$rc" "1"
contains "статус про нехватку"  "$(state)" "no space"
contains "назван размер"        "$(state)" "MB"
check    "ничего не установлено" "$(dat_n)" "0"

echo "=== все зеркала недоступны -> внятная ошибка, мусора нет ==="
rc="$(run MB_TEST_SIZE= MB_TEST_FREE_KB=900000 MB_TEST_FETCH_RC=1)"
check    "код возврата 1"        "$rc" "1"
contains "статус про зеркала"     "$(state)" "все зеркала недоступны"
check    "ничего не установлено"  "$(dat_n)" "0"

echo "=== первое зеркало ок -> обе базы, статус ok ==="
rc="$(run MB_TEST_SIZE=50000000 MB_TEST_FREE_KB=900000)"
check "код возврата 0"       "$rc" "0"
check "статус ok"            "$(state)" "ok"
check "установлены обе базы" "$(dat_n)" "2"

echo "=== фолбэк: живо только 3-е зеркало -> качаем с него, статус ok ==="
M="http://dead1 http://dead2 http://good.mirror"
rc="$(run MB_GEO_MIRRORS="$M" MB_TEST_OK="good.mirror" MB_TEST_FREE_KB=900000)"
check    "код возврата 0"        "$rc" "0"
check    "статус ok"             "$(state)" "ok"
check    "установлены обе базы"   "$(dat_n)" "2"
contains "скачано с живого зеркала" "$(out)" "good.mirror"

echo "=== места хватает, но сеть падает -> проходим precheck и упираемся в зеркала ==="
rc="$(run MB_TEST_SIZE=1000000 MB_TEST_FREE_KB=900000 MB_TEST_FETCH_RC=1)"
check    "код возврата 1"     "$rc" "1"
contains "статус про зеркала"  "$(state)" "все зеркала недоступны"

echo
echo "geo_test: $pass passed, $fail failed"
[ "$fail" = 0 ]
