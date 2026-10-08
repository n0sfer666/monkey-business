#!/bin/sh
# Регрессия direct-bypass в scripts/firewall/apply.sh: при MB_DIRECT_BYPASS=1 в ruleset появляются
# сеты mb_ru4/mb_ru6, prerouting @mb_ru4/6 return (ДО tproxy) и forward @mb_ru4/6 accept (ДО drop);
# при =0 — никаких упоминаний RU-сетов (грейсфул). Плюс force-сеты из MB_FORCE_PROXY: tproxy для них
# обязан стоять ВЫШЕ @mb_ru4 return, а drop в forward — ВЫШЕ @mb_ru4 accept (обе половины инварианта
# «явный выбор пользователя сильнее geo-обхода»). nft/ip стабятся (kernel-команды не нужны в CI).
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

# --- force-proxy: явный список пользователя сильнее ядерного RU-обхода (регрессия) ---
# Дефект: адрес, добавленный в custom_proxy, попадал в mb_ru4 (RU-диапазон) -> правило @mb_ru4 return
# срабатывало ДО tproxy, пакет уходил напрямую мимо Xray, а правило в xray.json было мёртвым кодом.
# Снаружи это выглядело как «список не применился». Порядок force-правила ВЫШЕ bypass-return —
# суть фикса, поэтому пинится явно.
runf() { # runf <MB_FORCE_PROXY> [BYPASS] [RUSET_DIR]
	: > "$T/ruleset"; : > "$T/nftcalls"
	PATH="$T:$PATH" MB_DIRECT_BYPASS="${2:-1}" MB_KILL_SWITCH=1 MB_RUSET_DIR="${3:-$T/empty}" \
		MB_FORCE_PROXY="$1" sh "$ROOT/scripts/firewall/apply.sh" >/dev/null 2>&1
}

runf '203.0.113.7, 2a03:e2c0::/32'
ok "force.set_v4"       "$(has x 'set mb_force4')" y
ok "force.set_v6"       "$(has x 'set mb_force6')" y
# Семейство в tproxy обязано быть явным: в inet-таблице рядом с `ip daddr` голое `tproxy to` даёт
# «conflicting protocols specified» и роняет ВЕСЬ документ — firewall молча остаётся прежним.
ok "force.pre_v4"        "$(has x '@mb_force4 .*tproxy ip to :12345')" y
ok "force.pre_v6"        "$(has x '@mb_force6 .*tproxy ip6 to :12345')" y
ok "force.above_bypass"  "$(before '@mb_force4' '@mb_ru4 return')" y
ok "force.above_bypass6" "$(before '@mb_force6' '@mb_ru6 return')" y
# Вторая половина того же инварианта — в forward. Без неё при упавшем Xray tproxy не находит сокет,
# пакет доезжает до forward и уходит наружу через @mb_ru4 accept: fail-open ровно для адреса,
# помеченного «только через туннель» (для не-RU адреса там сработал бы drop).
ok "force.fwd_v4"        "$(has x '@mb_force4 .*drop')" y
ok "force.fwd_v6"        "$(has x '@mb_force6 .*drop')" y
ok "force.fwd_above_ru"  "$(before '@mb_force4 .*drop' '@mb_ru4 accept')" y
ok "force.fwd_above_ru6" "$(before '@mb_force6 .*drop' '@mb_ru6 accept')" y
ok "force.elem_v4"       "$(hascall 'mb_force4 { 203.0.113.7 }')" y
ok "force.elem_v6"       "$(hascall 'mb_force6 { 2a03:e2c0::/32 }')" y
# DNS обязан остаться в dns_dnat: raw-UDP-53 через прокси не ходит, и список пользователя это не меняет
ok "force.dns_above"     "$(before 'th dport 53 return' '@mb_force4')" y
# Элементы грузятся ДО RU-сетов: иначе есть окно, где mb_ru4 уже полон, а mb_force4 ещё пуст, и
# пакет к форсированному RU-адресу уходит напрямую (TCP-сессия остаётся direct на весь свой срок).
runf '203.0.113.7' 1 "$T/ruset"
ok "force.elem_before_ru" "$(head -2 "$T/nftcalls" | tail -1)" "add element inet monkey_business mb_force4 { 203.0.113.7 }"

# Разбор списка: разделители и «мусор» — ровно как в classifyList() (src/generator/routing.uc),
# иначе firewall и xray.json разойдутся на одной и той же строке.
runf '1.2.3.4
 5.6.7.8 ,# комментарий
example.com, geosite:google, geoip:cn, *.corp.local'
ok "force.sep_newline"  "$(hascall 'mb_force4 { 1.2.3.4 }')" y
ok "force.trim"         "$(hascall 'mb_force4 { 5.6.7.8 }')" y
ok "force.no_comment"   "$(hascall 'комментарий')" n
ok "force.no_domains"   "$(hascall 'example.com|geosite|geoip|corp.local')" n

# Битый ввод: он похож на адрес, но nft его отвергнет. Проверка строгая, а элементы грузятся
# ПООДИНОЧКЕ — иначе одна опечатка пользователя молча отменяла бы фикс для всех соседних адресов.
runf '999.999.999.999, 256.1.1.1, 1.2.3.4/33, 2a03::/999, 203.0.113.7'
ok "force.bad_octet"    "$(hascall '999')" n
ok "force.bad_octet256" "$(hascall '256.1.1.1')" n
ok "force.bad_prefix4"  "$(hascall '1.2.3.4/33')" n
ok "force.bad_prefix6"  "$(hascall '2a03::/999')" n
ok "force.good_survives" "$(hascall 'mb_force4 { 203.0.113.7 }')" y
ok "force.per_element"  "$(ncalls)" 2

# только v4 в списке -> сета и правила v6 нет (лишний lookup на каждый пакет), и наоборот
runf '10.20.30.40/29'
ok "force.v4only_no_v6"  "$(has x 'mb_force6')" n
runf '2a03:e2c0::/32'
ok "force.v6only_no_v4"  "$(has x 'mb_force4')" n

# пустой список -> ruleset и число транзакций ровно как до фикса
runf ''
ok "force.empty_no_set"  "$(has x 'mb_force')" n
ok "force.empty_calls"   "$(ncalls)" 1

# BYPASS=0 -> force не нужен: без RU-обхода весь tcp/udp и так уходит в tproxy
runf '203.0.113.7' 0
ok "force.b0_no_set"   "$(has x 'mb_force')" n
ok "force.b0_no_elem"  "$(hascall 'mb_force')" n

# --- BYPASS=0: ни одного упоминания RU-сетов ---
run 0
ok "b0.no_set"  "$(has x 'mb_ru4')" n
ok "b0.no_set6" "$(has x 'mb_ru6')" n
# базовый функционал на месте
ok "b0.tproxy"  "$(has x 'tproxy to :12345')" y
ok "b0.drop"    "$(has x 'drop')" y

printf '\nfirewall_test: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
