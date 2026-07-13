#!/bin/sh
# Сборка nftables-сетов RU-CIDR для direct-bypass (RU/приватный трафик минует Xray, маршрутизируется
# ядром нативно). Источник — Loyalsoldier text/ru.txt (та же экосистема, что geoip.dat -> консистентно
# с правилом geoip:ru в Xray). Команды:
#   ruset.sh build    # скачать ru.txt (URL из UCI geo.ru_set_url или дефолт), сгенерить ru4.nft/ru6.nft, перезагрузить сет
#   ruset.sh reload   # перезалить уже сгенерённые ru4.nft/ru6.nft в живую таблицу (без полного reapply)
#   ruset.sh status   # JSON: state/v4/v6 (количество элементов)
# Идемпотентность: build пропускает перегенерацию, если sha256 источника не изменился и файлы на месте.
set -u

DIR="${MB_RUSET_DIR:-/usr/share/monkey-business}"
STATE="/tmp/mb-ruset.state"
TABLE="inet monkey_business"
DEFAULT_URL="https://raw.githubusercontent.com/Loyalsoldier/geoip/release/text/ru.txt"
RU4="$DIR/ru4.nft"
RU6="$DIR/ru6.nft"

LIB="${MB_LIB_DIR:-$(dirname "$0")}"
# без fetch.sh падать нельзя: status дёргает rpcd на каждый рендер дашборда и ждёт JSON
if [ -r "$LIB/fetch.sh" ]; then
	# shellcheck source-path=SCRIPTDIR source=fetch.sh
	. "$LIB/fetch.sh"
else
	mb_fetch() { echo "fetch.sh not found in $LIB" >&2; return 1; }
fi

uci_get() { uci -q get "monkey-business.geo.$1" 2>/dev/null || echo ""; }
set_state() { echo "$1" >"$STATE"; }

sha_of() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

# emit_set <setname> <outfile> <listfile> -> 0 если набор непуст и файл записан, 1 если пусто
emit_set() {
	set="$1"; out="$2"; lst="$3"
	if [ ! -s "$lst" ]; then rm -f "$out"; return 1; fi
	{
		printf 'add element %s %s { ' "$TABLE" "$set"
		awk 'NF { if (c++) printf ", "; printf "%s", $1 } END { printf " }\n" }' "$lst"
	} >"$out.tmp" && mv -f "$out.tmp" "$out"
}

# generate <src> -> разбивает на валидные v4/v6 CIDR, генерит ru4.nft/ru6.nft
generate() {
	src="$1"
	tmp4="$(mktemp "${TMPDIR:-/tmp}/mb-ru4.XXXXXX")" || return 1
	tmp6="$(mktemp "${TMPDIR:-/tmp}/mb-ru6.XXXXXX")" || { rm -f "$tmp4"; return 1; }
	grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$' "$src" >"$tmp4" || true
	grep -E '^[0-9a-fA-F:]+/[0-9]+$' "$src" | grep ':' >"$tmp6" || true
	emit_set mb_ru4 "$RU4" "$tmp4"; r4=$?
	emit_set mb_ru6 "$RU6" "$tmp6"; r6=$?
	rm -f "$tmp4" "$tmp6"
	[ "$r4" = 0 ] || [ "$r6" = 0 ]
}

# reload_live -> если таблица существует, перезалить сеты без полного reapply
reload_live() {
	nft list table inet monkey_business >/dev/null 2>&1 || return 0
	if [ -f "$RU4" ]; then
		nft flush set inet monkey_business mb_ru4 2>/dev/null || true
		nft -f "$RU4" 2>/dev/null || true
	fi
	if [ -f "$RU6" ]; then
		nft flush set inet monkey_business mb_ru6 2>/dev/null || true
		nft -f "$RU6" 2>/dev/null || true
	fi
}

cmd_build() {
	# старый sha читаем ДО set_state (он затирает STATE) — иначе идемпотентность не сработает
	old="$(awk -F= '/^sha=/{print $2}' "$STATE" 2>/dev/null || echo "")"
	set_state "updating"
	url="$(uci_get ru_set_url)"
	[ -n "$url" ] || url="${MB_RUSET_URL:-$DEFAULT_URL}"
	tmp="$(mktemp "${TMPDIR:-/tmp}/mb-ru.dl.XXXXXX")" || { set_state "error: mktemp failed"; return 1; }
	if ! mb_fetch "$url" "$tmp"; then set_state "error: download failed"; rm -f "$tmp"; return 1; fi
	if [ ! -s "$tmp" ]; then set_state "error: empty source"; rm -f "$tmp"; return 1; fi
	new="$(sha_of "$tmp")"
	if [ -n "$new" ] && [ "$new" = "$old" ] && [ -f "$RU4" ]; then
		rm -f "$tmp"
		c4="$(count_elems mb_ru4 "$RU4")"; c6="$(count_elems mb_ru6 "$RU6")"
		printf 'state=ok\nsha=%s\nv4=%s\nv6=%s\n' "$new" "$c4" "$c6" >"$STATE"
		reload_live
		echo "ru-set: up to date (sha256 match)"
		return 0
	fi
	if ! generate "$tmp"; then set_state "error: no valid CIDR in source"; rm -f "$tmp"; return 1; fi
	rm -f "$tmp"
	c4="$(count_elems mb_ru4 "$RU4")"; c6="$(count_elems mb_ru6 "$RU6")"
	printf 'state=ok\nsha=%s\nv4=%s\nv6=%s\n' "$new" "$c4" "$c6" >"$STATE"
	reload_live
	echo "ru-set built: v4=$c4 v6=$c6"
}

# count_elems <setname> <file> -> число элементов в сгенерённом файле
count_elems() {
	[ -f "$2" ] || { echo 0; return; }
	tr ',' '\n' <"$2" | grep -cE '/[0-9]+' 2>/dev/null || echo 0
}

cmd_status() {
	st="idle"; v4=0; v6=0
	if [ -f "$STATE" ]; then
		st="$(awk -F= '/^state=/{print $2}' "$STATE" 2>/dev/null || echo idle)"
		v4="$(awk -F= '/^v4=/{print $2}' "$STATE" 2>/dev/null || echo 0)"
		v6="$(awk -F= '/^v6=/{print $2}' "$STATE" 2>/dev/null || echo 0)"
	fi
	[ -n "$st" ] || st="idle"
	printf '{"state":"%s","v4":%s,"v6":%s}\n' "$st" "${v4:-0}" "${v6:-0}"
}

case "${1:-}" in
	build)  cmd_build ;;
	reload) reload_live ;;
	status) cmd_status ;;
	*) echo "usage: $0 {build|reload|status}" >&2; exit 2 ;;
esac
