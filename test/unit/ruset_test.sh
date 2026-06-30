#!/bin/sh
# Регрессия root/usr/share/monkey-business/ruset.sh: build разбивает источник на валидные v4/v6 CIDR,
# генерит ru4.nft/ru6.nft в nft-element-формате, отбрасывает мусор, идемпотентен по sha256, status даёт
# корректный JSON. Сеть стабится (curl печатает фикстуру); nft/uci отсутствуют -> reload no-op грейсфул.
set -u

SELF_DIR=$(dirname "$0")
ROOT="$SELF_DIR/../.."
RUSET="$ROOT/root/usr/share/monkey-business/ruset.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# фикстура: 3 v4 CIDR, 2 v6 CIDR, мусор (без префикса, текст, пусто)
cat > "$T/ru.txt" <<'FIX'
2.16.20.0/23
77.88.8.0/24
95.108.0.0/16
2001:470:5:5c::/64
2a02:6b8::/32
garbage-line
1.2.3.4
FIX

# стаб curl: печатает фикстуру в выходной файл (-o out url)
cat > "$T/curl" <<STUB
#!/bin/sh
out=""; for a in "\$@"; do [ "\$prev" = "-o" ] && out="\$a"; prev="\$a"; done
cat "$T/ru.txt" > "\$out"
STUB
chmod +x "$T/curl"

build() { PATH="$T:$PATH" MB_RUSET_DIR="$T" MB_RUSET_URL="http://x/ru.txt" sh "$RUSET" build 2>/dev/null; }
status() { PATH="$T:$PATH" MB_RUSET_DIR="$T" sh "$RUSET" status 2>/dev/null; }

PASS=0; FAIL=0
ok() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL $1: want[$3] got[$2]"; fi; }
has() { grep -q "$2" "$1" && echo y || echo n; }

build >/dev/null

# 1. файлы созданы, корректный nft-element-формат
ok "ru4.exists"  "$([ -f "$T/ru4.nft" ] && echo y || echo n)" y
ok "ru6.exists"  "$([ -f "$T/ru6.nft" ] && echo y || echo n)" y
ok "ru4.header"  "$(has "$T/ru4.nft" 'add element inet monkey_business mb_ru4 {')" y
ok "ru6.header"  "$(has "$T/ru6.nft" 'add element inet monkey_business mb_ru6 {')" y

# 2. v4 идут в ru4, v6 в ru6, без перекрёстка
ok "ru4.has_v4"  "$(has "$T/ru4.nft" '77.88.8.0/24')" y
ok "ru4.no_v6"   "$(has "$T/ru4.nft" '2001:470')" n
ok "ru6.has_v6"  "$(has "$T/ru6.nft" '2a02:6b8::/32')" y
ok "ru6.no_v4"   "$(has "$T/ru6.nft" '77.88')" n

# 3. мусор отброшен (нет CIDR-префикса / не IP)
ok "ru4.no_garbage" "$(has "$T/ru4.nft" 'garbage')" n
ok "ru4.no_bare_ip" "$(has "$T/ru4.nft" '1.2.3.4')" n

# 4. status JSON: state=ok, корректные счётчики (3 v4, 2 v6)
ST="$(status)"
ok "status.ok" "$(echo "$ST" | grep -q '"state":"ok"' && echo y || echo n)" y
ok "status.v4" "$(echo "$ST" | grep -q '"v4":3' && echo y || echo n)" y
ok "status.v6" "$(echo "$ST" | grep -q '"v6":2' && echo y || echo n)" y

# 5. идемпотентность: второй build с тем же содержимым -> "up to date"
OUT2="$(build)"
ok "idempotent" "$(echo "$OUT2" | grep -qi 'up to date' && echo y || echo n)" y

printf '\nruset_test: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
