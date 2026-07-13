#!/bin/sh
# Юнит-тест общей загрузки (root/usr/share/monkey-business/fetch.sh). Моки curl/pidof через PATH.
# Главное, что защищаем: socks-фолбэк идёт ТОЛЬКО когда прямая загрузка провалилась и xray жив,
# а неудачная загрузка не оставляет за собой обрезанный файл (его бы приняли за валидный).
set -u

SELF_DIR=$(dirname "$0")
LIB="$SELF_DIR/../../root/usr/share/monkey-business/fetch.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

pass=0; fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "  FAIL: $1"; }
check() { if [ "$2" = "$3" ]; then ok; else bad "$1: ждали '$3', получили '$2'"; fi; }

mkdir -p "$T/bin"

# curl-мок: пишет свои аргументы в лог; успех/провал задаётся файлами-флагами
cat >"$T/bin/curl" <<EOF
#!/bin/sh
echo "\$*" >> "$T/curl.log"
out=""; prev=""
for a in "\$@"; do
	[ "\$prev" = "-o" ] && out="\$a"
	prev="\$a"
done
case "\$*" in
	*socks5h*) [ -f "$T/socks_ok" ] || exit 7
	           printf 'via-socks' > "\$out"; exit 0 ;;
	*)         [ -f "$T/direct_ok" ] || { printf 'partial' > "\$out"; exit 28; }
	           printf 'via-direct' > "\$out"; exit 0 ;;
esac
EOF
cat >"$T/bin/pidof" <<EOF
#!/bin/sh
[ -f "$T/xray_up" ] && { echo 123; exit 0; }
exit 1
EOF
chmod +x "$T/bin/curl" "$T/bin/pidof"
# PATH внутри прогона — только мок-каталог (иначе command -v нашёл бы системный curl),
# поэтому реальные утилиты, которые нужны самому fetch.sh, кладём туда же
ln -sf /bin/rm "$T/bin/rm"

# fetch.sh проверяет наличие curl через command -v -> PATH только из мок-каталога
run() {
	rm -f "$T/curl.log" "$T/out"
	rc=0
	PATH="$T/bin" /bin/sh -c ". '$LIB'; mb_fetch http://x/f '$T/out'" 2>"$T/err" || rc=$?
	echo "$rc"
}
body()    { cat "$T/out" 2>/dev/null || echo "<нет файла>"; }
curl_n()  { if [ -f "$T/curl.log" ]; then wc -l < "$T/curl.log" | tr -d ' '; else echo 0; fi; }

echo
echo "=== прямая загрузка удалась -> socks не трогаем ==="
: >"$T/direct_ok"; : >"$T/xray_up"; : >"$T/socks_ok"
check "код возврата 0" "$(run)" "0"
check "файл от direct" "$(body)" "via-direct"
check "curl звался один раз" "$(curl_n)" "1"
check "socks не использован" "$(grep -c socks5h "$T/curl.log" || true)" "0"

echo "=== direct провалился, xray жив -> фолбэк в socks ==="
rm -f "$T/direct_ok"
check "код возврата 0" "$(run)" "0"
check "файл от socks" "$(body)" "via-socks"
check "curl звался дважды" "$(curl_n)" "2"
check "второй вызов через socks5h" "$(grep -c 'socks5h://127.0.0.1:10808' "$T/curl.log")" "1"

echo "=== direct провалился, xray НЕ запущен -> фолбэка нет, ошибка ==="
rm -f "$T/xray_up"
check "код возврата 1" "$(run)" "1"
check "обрезанный файл удалён" "$(body)" "<нет файла>"
check "socks не пробовали" "$(grep -c socks5h "$T/curl.log" || true)" "0"

echo "=== direct и socks провалились -> ошибка, мусора не осталось ==="
: >"$T/xray_up"; rm -f "$T/socks_ok"
check "код возврата 1" "$(run)" "1"
check "файла нет" "$(body)" "<нет файла>"

echo "=== socks-адрес переопределяется через MB_FETCH_SOCKS ==="
: >"$T/socks_ok"
rm -f "$T/curl.log" "$T/out"
PATH="$T/bin" MB_FETCH_SOCKS="10.0.0.9:1080" \
	/bin/sh -c ". '$LIB'; mb_fetch http://x/f '$T/out'" 2>/dev/null
check "использован заданный socks" "$(grep -c 'socks5h://10.0.0.9:1080' "$T/curl.log")" "1"

echo "=== curl отсутствует, есть wget -> direct через wget, socks невозможен ==="
rm -f "$T/bin/curl" "$T/out"
cat >"$T/bin/wget" <<EOF
#!/bin/sh
printf 'via-wget' > "$T/out"
EOF
chmod +x "$T/bin/wget"
rc=0
PATH="$T/bin" /bin/sh -c ". '$LIB'; mb_fetch http://x/f '$T/out'" 2>/dev/null || rc=$?
check "код возврата 0" "$rc" "0"
check "файл от wget" "$(body)" "via-wget"

echo
echo "fetch_test: $pass passed, $fail failed"
[ "$fail" = 0 ]
