#!/bin/sh
# Юнит-тест hysteria.sh: перебор зеркал, отказ на неизвестной архитектуре, отбраковка не-бинаря,
# проверка sha256, JSON статуса. fetch.sh подменяется фейком, uname/df/uci — стабами через PATH.
set -u

SELF_DIR=$(dirname "$0")
HY="$SELF_DIR/../../root/usr/share/monkey-business/hysteria.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

pass=0; fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "  FAIL: $1"; }
check()    { if [ "$2" = "$3" ]; then ok; else bad "$1: ждали '$3', получили '$2'"; fi; }
contains() { case "$2" in *"$3"*) ok ;; *) bad "$1: в '$2' нет '$3'" ;; esac; }

mkdir -p "$T/bin" "$T/lib"

# Фейк fetch.sh: файл сумм отдаётся только при MB_TEST_SHA, в формате апстрима (строка на ассет,
# путь с префиксом build/). Бинарь скачивается лишь с зеркала, содержащего MB_TEST_OK; содержимое —
# псевдо-ELF (MB_TEST_BODY=html даёт страницу ошибки). Каждый запрос пишется в MB_TEST_FETCH_LOG
# вместе с действующим лимитом времени — по нему проверяется и порядок шагов, и укороченный таймаут.
cat >"$T/lib/fetch.sh" <<'EOF'
mb_fetch() {
	[ -z "${MB_TEST_FETCH_LOG:-}" ] || echo "$1 t=${MB_FETCH_TIMEOUT:-}" >> "$MB_TEST_FETCH_LOG"
	case "$1" in
		*/hashes.txt)
			[ -n "${MB_TEST_SHA:-}" ] || return 1
			# MB_TEST_SHA_ALT_ON=<кусок url> — это зеркало отдаёт ДРУГУЮ сумму (подмена).
			case "$1" in
				*"${MB_TEST_SHA_ALT_ON:-__nomatch__}"*)
					echo "${MB_TEST_SHA_ALT:-beef}  build/hysteria-linux-arm64" > "$2"; return 0 ;;
			esac
			# Соседние строки не декоративны: arm64 стоит рядом с arm, а имя ассета одного является
			# префиксом другого — на этом и проверяется якорь в sha_from_hashes.
			{
				echo "${MB_TEST_SHA_ARM:-1111111111}  build/hysteria-linux-arm"
				echo "$MB_TEST_SHA  build/hysteria-linux-arm64"
				echo "2222222222  build/hysteria-windows-amd64.exe"
			} > "$2"
			return 0 ;;
	esac
	[ "${MB_TEST_FETCH_RC:-0}" = 0 ] || return 1
	if [ -n "${MB_TEST_OK:-}" ]; then case "$1" in *"$MB_TEST_OK"*) : ;; *) return 1 ;; esac; fi
	if [ "${MB_TEST_BODY:-elf}" = html ]; then
		echo "<html>404</html>" > "$2"
		return 0
	fi
	# ELF-магия в первых байтах (её проверяет validate), дальше — shell: скрипт запускает
	# скачанный файл, и sh исполняет неизвестный формат как скрипт.
	{ printf '\177ELF\n'; cat <<'BIN'
[ "$1" = version ] && echo "Version: v2.6.0"
exit 0
BIN
	} > "$2"
	return 0
}
EOF

# Псевдо-бинарь исполняется самим скриптом (validate) и в status: печатает версию.
cat >"$T/bin/sh-elf-runner" <<'EOF'
#!/bin/sh
[ "${1:-}" = version ] && echo "Version: v2.6.0"
exit 0
EOF
chmod +x "$T/bin/sh-elf-runner"
cat >"$T/bin/uname" <<'EOF'
#!/bin/sh
echo "${MB_TEST_ARCH:-aarch64}"
EOF
cat >"$T/bin/df" <<'EOF'
#!/bin/sh
echo "Filesystem 1K-blocks Used Available Use% Mounted"
echo "stub 1000000 0 ${MB_TEST_FREE_KB:-900000} 0% /"
EOF
printf '#!/bin/sh\nexit 1\n' > "$T/bin/uci"
cat >"$T/bin/sha256sum" <<'EOF'
#!/bin/sh
echo "${MB_TEST_LOCAL_SHA:-deadbeef}  $1"
EOF
chmod +x "$T/bin/uname" "$T/bin/df" "$T/bin/uci" "$T/bin/sha256sum"

BIN="$T/hysteria"; STATEF="$T/hy.state"; OUTF="$T/hy.out"
run() { # run [ENV=..] <cmd>; печатает rc
	rc=0
	env PATH="$T/bin:$PATH" MB_LIB_DIR="$T/lib" MB_HY_BIN="$BIN" MB_HY_STATE="$STATEF" \
		MB_HY_CONF="$T/hysteria.json" MB_HY_LOCK="$T/hy.lock" TMPDIR="$T" "$@" >"$OUTF" 2>/dev/null || rc=$?
	echo "$rc"
}
install_run() { rm -f "$BIN" "$STATEF"; run "$@" sh "$HY" install; }
state() { cat "$STATEF" 2>/dev/null || echo "<нет>"; }
out()   { cat "$OUTF" 2>/dev/null; }

echo
echo "=== неизвестная архитектура -> отказ до сети, внятный статус ==="
rc="$(install_run MB_TEST_ARCH=vax)"
check    "код возврата 1"      "$rc" "1"
contains "статус про архитектуру" "$(state)" "unsupported architecture"
check    "бинарь не установлен"   "$([ -f "$BIN" ] && echo y || echo n)" "n"

# MB_TEST_SHA здесь и ниже задан намеренно: сумма собирается ПЕРВОЙ, и без неё прогон не дошёл бы
# до фазы скачивания, которую эти случаи и проверяют.
echo "=== все зеркала недоступны -> внятная ошибка, мусора нет ==="
rc="$(install_run MB_TEST_FETCH_RC=1 MB_TEST_SHA=cafe)"
check    "код возврата 1"     "$rc" "1"
contains "статус про зеркала"  "$(state)" "все зеркала недоступны"
check    "бинарь не установлен" "$([ -f "$BIN" ] && echo y || echo n)" "n"

echo "=== зеркало отдало HTML вместо бинаря -> отбраковка, не ставим ==="
rc="$(install_run MB_TEST_BODY=html MB_TEST_SHA=cafe)"
check    "код возврата 1"       "$rc" "1"
contains "статус про не-ELF"     "$(state)" "ELF"
check    "бинарь не установлен"  "$([ -f "$BIN" ] && echo y || echo n)" "n"

echo "=== контрольная сумма не сошлась -> отказ ==="
rc="$(install_run MB_TEST_SHA=cafe MB_TEST_LOCAL_SHA=beef)"
check    "код возврата 1"      "$rc" "1"
contains "статус про сумму"     "$(state)" "контрольная сумма"

echo "=== места мало -> отказ ДО скачивания ==="
rc="$(install_run MB_TEST_FREE_KB=1000)"
check    "код возврата 1"   "$rc" "1"
contains "статус про место"  "$(state)" "40MB"

# Бинарь ляжет в /usr/bin и будет исполняться от root, а зеркала — gh-прокси, т.е. MITM по
# устройству. Непроверяемый бинарь не ставим вообще: «второй протокол не заработал» дешевле.
echo "=== суммы нет ни на одном зеркале -> НЕ ставим и НЕ качаем 20МБ ==="
: > "$T/fetch.log"
rc="$(install_run MB_TEST_FETCH_LOG="$T/fetch.log")"
check    "код возврата 1"      "$rc" "1"
contains "статус про сумму"     "$(state)" "не опубликована"
check    "бинарь не установлен"  "$([ -f "$BIN" ] && echo y || echo n)" "n"
check    "за бинарём не ходили"  "$(grep -c 'hysteria-linux-arm64 ' "$T/fetch.log")" "0"

# Файл сумм — килобайты: на мёртвом зеркале он не должен стоить столько же, сколько 20МБ бинарь.
echo "=== файл сумм качается с укороченным лимитом, общий не затирается ==="
: > "$T/fetch.log"
rc="$(install_run MB_TEST_FETCH_LOG="$T/fetch.log" MB_TEST_SHA=cafe MB_TEST_LOCAL_SHA=cafe)"
check    "код возврата 0"       "$rc" "0"
contains "у файла сумм свой лимит" "$(grep hashes.txt "$T/fetch.log" | head -1)" "t=30"
check    "у бинаря лимит прежний"  "$(grep -c 'hysteria-linux-arm64 t=30' "$T/fetch.log")" "0"

# Сумма берётся по ИМЕНИ ассета: без якоря hysteria-linux-arm подцепил бы строку arm64, и сверка
# упала бы с «сумма не сошлась» — то есть увела бы от настоящей причины.
echo "=== имя ассета якорится: arm не берёт сумму от arm64 ==="
rc="$(install_run MB_TEST_ARCH=armv7l MB_TEST_SHA=cafe MB_TEST_SHA_ARM=abc123 MB_TEST_LOCAL_SHA=abc123)"
check    "код возврата 0" "$rc" "0"
check    "статус ok"      "$(state)" "ok"

echo "=== зеркала отдают РАЗНЫЕ суммы (подмена) -> НЕ ставим ==="
rc="$(install_run MB_TEST_SHA=cafe MB_TEST_LOCAL_SHA=cafe MB_TEST_SHA_ALT_ON=gh-proxy.com)"
check    "код возврата 1"      "$rc" "1"
contains "статус про расхождение" "$(state)" "разные контрольные суммы"
check    "бинарь не установлен"  "$([ -f "$BIN" ] && echo y || echo n)" "n"

echo "=== установка уже идёт -> второй запуск отказывает, не трогая STATE ==="
rm -f "$BIN"; mkdir -p "$T/hy.lock"; echo running > "$STATEF"
rc="$(run sh "$HY" install)"
check "код возврата 1" "$rc" "1"
check "STATE не тронут" "$(state)" "running"
rmdir "$T/hy.lock"

echo "=== фолбэк: живо только 3-е зеркало -> ставим с него ==="
M="http://dead1 http://dead2 http://good.mirror"
rc="$(install_run MB_HY_MIRRORS="$M" MB_TEST_OK=good.mirror MB_TEST_SHA=cafe MB_TEST_LOCAL_SHA=cafe)"
check    "код возврата 0"        "$rc" "0"
check    "статус ok"             "$(state)" "ok"
contains "скачано с живого зеркала" "$(out)" "good.mirror"
check    "бинарь на месте"        "$([ -x "$BIN" ] && echo y || echo n)" "y"

echo "=== status: JSON с installed/version ==="
cp "$T/bin/sh-elf-runner" "$BIN"
rc="$(run sh "$HY" status)"
check    "код возврата 0"   "$rc" "0"
contains "installed=true"    "$(out)" '"installed":true'
contains "версия из бинаря"   "$(out)" 'v2.6.0'

echo "=== remove снимает бинарь и конфиг ==="
: > "$T/hysteria.json"
rc="$(run sh "$HY" remove)"
check "код возврата 0"     "$rc" "0"
check "бинаря нет"         "$([ -f "$BIN" ] && echo y || echo n)" "n"
check "конфига нет"        "$([ -f "$T/hysteria.json" ] && echo y || echo n)" "n"

echo "=== status без бинаря -> installed=false ==="
rc="$(run sh "$HY" status)"
contains "installed=false" "$(out)" '"installed":false'

# Битый JSON рантайм молча подменяет на {state:'idle'} — причина отказа исчезла бы из UI ровно
# тогда, когда она нужна.
echo "=== status: кавычка в состоянии не ломает JSON ==="
printf 'error: mirror said "no"\n' > "$STATEF"
rc="$(run sh "$HY" status)"
contains "кавычка экранирована" "$(out)" '\"no\"'
check    "строка одна"          "$(out | wc -l | tr -d ' ')" "1"

echo
echo "hysteria_test: $pass passed, $fail failed"
[ "$fail" = 0 ]
