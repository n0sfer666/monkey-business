#!/bin/sh
# Регрессия direct-bypass в scripts/firewall/apply.sh: при MB_DIRECT_BYPASS=1 в ruleset появляются
# сеты mb_ru4/mb_ru6, prerouting @mb_ru4/6 return (ДО tproxy) и forward @mb_ru4/6 accept (ДО drop);
# при =0 — никаких упоминаний RU-сетов (грейсфул). nft/ip стабятся (kernel-команды не нужны в CI).
set -u

SELF_DIR=$(dirname "$0")
ROOT="$SELF_DIR/../.."
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# стаб nft: аргументы каждого вызова -> $T/nftcalls (по строке на вызов), stdin "nft -f -" ->
# $T/ruleset; прочие вызовы — no-op. ip — no-op.
cat > "$T/nft" <<STUB
#!/bin/sh
echo "\$*" >> "$T/nftcalls"
if [ "\$1" = "-f" ] && [ "\$2" = "-" ]; then cat > "$T/ruleset"; exit 0; fi
exit 0
STUB
printf '#!/bin/sh\nexit 0\n' > "$T/ip"
chmod +x "$T/nft" "$T/ip"

run() { # run <BYPASS> [RUSET_DIR] ; генерит $T/ruleset и $T/nftcalls
	: > "$T/ruleset"; : > "$T/nftcalls"
	PATH="$T:$PATH" MB_DIRECT_BYPASS="$1" MB_KILL_SWITCH=1 MB_RUSET_DIR="${2:-$T/empty}" \
		sh "$ROOT/scripts/firewall/apply.sh" >/dev/null 2>&1
}

PASS=0; FAIL=0
ok() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL $1: want[$3] got[$2]"; fi; }
has() { grep -q "$2" "$T/ruleset" && echo y || echo n; }
hascall() { grep -q "$1" "$T/nftcalls" && echo y || echo n; }
ncalls() { wc -l < "$T/nftcalls" | tr -d ' '; }
# before A B -> y если строка A встречается РАНЬШЕ строки B в ruleset
before() {
	la=$(grep -n "$1" "$T/ruleset" | head -1 | cut -d: -f1)
	lb=$(grep -n "$2" "$T/ruleset" | head -1 | cut -d: -f1)
	{ [ -n "$la" ] && [ -n "$lb" ] && [ "$la" -lt "$lb" ]; } && echo y || echo n
}

# --- BYPASS=1: сеты + правила присутствуют ---
run 1
ok "b1.set_v4"    "$(has x 'set mb_ru4')" y
ok "b1.set_v6"    "$(has x 'set mb_ru6')" y
ok "b1.pre_v4"    "$(has x '@mb_ru4 return')" y
ok "b1.pre_v6"    "$(has x '@mb_ru6 return')" y
ok "b1.fwd_v4"    "$(has x '@mb_ru4 accept')" y
ok "b1.fwd_v6"    "$(has x '@mb_ru6 accept')" y
# порядок: bypass-return ДО tproxy, bypass-accept ДО drop (иначе утечка/неэффективно)
ok "b1.pre_before_tproxy" "$(before '@mb_ru4 return' 'tproxy')" y
ok "b1.fwd_before_drop"   "$(before '@mb_ru4 accept' 'drop')" y

# --- атомарность свопа таблицы ---
# Отдельный `nft delete table` перед созданием открывал окно без kill-switch и без tproxy: форвард
# LAN->WAN уходил открытым через fw4 на каждом reload. Своп обязан идти одним документом nft -f
# (add -> delete -> create), иначе окно возвращается. Здесь MB_RUSET_DIR пуст, поэтому вызов ровно
# один — область гарантии именно своп таблицы; про элементы RU-сетов см. блок ruset ниже.
ok "atomic.swap_one_call"    "$(ncalls)" 1
ok "atomic.no_bare_delete"   "$(hascall '^delete table')" n
ok "atomic.delete_in_doc"    "$(has x '^delete table inet monkey_business$')" y
ok "atomic.add_before_del"   "$(before '^table inet monkey_business$' '^delete table')" y
ok "atomic.create_after_del" "$(before '^delete table' '^table inet monkey_business {')" y

# --- элементы RU-сетов: отдельные транзакции ПОСЛЕ свопа, и это осознанно ---
# Инлайнить ru4.nft/ru6.nft в тот же документ нельзя: битый или обрезанный файл сетов уронил бы
# документ целиком, а на загрузке (прежней таблицы нет) это firewall без kill-switch и без tproxy —
# LAN светит в открытую сеть. Поэтому сеты грузятся отдельно и не фатально: худший случай — пустой
# bypass (RU-трафик идёт через туннель), а не отсутствие правил.
mkdir -p "$T/ruset"
printf 'add element inet monkey_business mb_ru4 { 1.2.3.0/24 }\n' > "$T/ruset/ru4.nft"
printf 'add element inet monkey_business mb_ru6 { 2a00::/32 }\n' > "$T/ruset/ru6.nft"
run 1 "$T/ruset"
ok "ruset.swap_first"   "$(head -1 "$T/nftcalls")" "-f -"
ok "ruset.calls"        "$(ncalls)" 3
ok "ruset.v4_loaded"    "$(hascall 'ru4.nft')" y
ok "ruset.v6_loaded"    "$(hascall 'ru6.nft')" y

# --- BYPASS=0: ни одного упоминания RU-сетов ---
run 0
ok "b0.no_set"  "$(has x 'mb_ru4')" n
ok "b0.no_set6" "$(has x 'mb_ru6')" n
# базовый функционал на месте
ok "b0.tproxy"  "$(has x 'tproxy to :12345')" y
ok "b0.drop"    "$(has x 'drop')" y

printf '\nfirewall_test: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
