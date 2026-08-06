#!/bin/sh
# Установка клиента hysteria2 (один статический бинарь) с перебором зеркал и валидацией.
#   hysteria.sh install   # скачать под текущую архитектуру, проверить, положить в /usr/bin/hysteria
#   hysteria.sh status    # JSON: installed/version/state
#   hysteria.sh remove    # снять бинарь и конфиг клиента
#
# Бинарь не пакуем в ipk и не тянем из apk: в feeds ImmortalWrt hysteria нет, а вшивать 15МБ в пакет
# ради второго протокола дорого. Логика та же, что у geo.sh: зеркала -> скачать -> sha256 -> проверить
# запуском -> атомарно поставить. Отличие от geo.sh: там данные, тут исполняемое под root, поэтому
# сумма обязательна (collect_sha) и без неё установка отменяется.
set -u

DEST="${MB_HY_BIN:-/usr/bin/hysteria}"
CONF="${MB_HY_CONF:-/etc/monkey-business/hysteria.json}"
STATE="${MB_HY_STATE:-/tmp/mb-hysteria.state}"
LOCK="${MB_HY_LOCK:-/tmp/mb-hysteria.lock}"
# GitHub у RU-провайдеров заблокирован, а качать нужно ДО поднятия туннеля (это и есть клиент
# туннеля) -> gh-прокси идут первыми, сам github.com остаётся последним фолбэком.
DEFAULT_MIRRORS="https://ghfast.top/https://github.com/apernet/hysteria/releases/latest/download https://ghproxy.net/https://github.com/apernet/hysteria/releases/latest/download https://gh-proxy.com/https://github.com/apernet/hysteria/releases/latest/download https://github.com/apernet/hysteria/releases/latest/download"

LIB="${MB_LIB_DIR:-$(dirname "$0")}"
# без fetch.sh падать нельзя: status дёргается rpcd на каждый рендер дашборда и ждёт JSON
if [ -r "$LIB/fetch.sh" ]; then
	# shellcheck source-path=SCRIPTDIR source=fetch.sh
	. "$LIB/fetch.sh"
else
	mb_fetch() { echo "fetch.sh not found in $LIB" >&2; return 1; }
fi

set_state() { echo "$1" >"$STATE"; }

mirrors() {
	m="$(uci -q get monkey-business.hysteria.mirrors 2>/dev/null || echo "")"
	[ -n "$m" ] && { echo "$m"; return; }
	echo "${MB_HY_MIRRORS:-$DEFAULT_MIRRORS}"
}

# Имя релизного ассета по архитектуре. Неизвестную архитектуру НЕ угадываем: скачанный не тот бинарь
# упадёт уже в рантайме, а причина будет выглядеть как «hysteria не подключается».
asset() {
	case "$(uname -m)" in
		aarch64|arm64) echo "hysteria-linux-arm64" ;;
		x86_64|amd64)  echo "hysteria-linux-amd64" ;;
		armv7*|armv6*|arm) echo "hysteria-linux-arm" ;;
		i386|i686)     echo "hysteria-linux-386" ;;
		mipsel|mipsle) echo "hysteria-linux-mipsle" ;;
		riscv64)       echo "hysteria-linux-riscv64" ;;
		s390x)         echo "hysteria-linux-s390x" ;;
		*) return 1 ;;
	esac
}

free_kb() { df -k "$1" 2>/dev/null | awk 'NR>1{print $4; exit}'; }

sha_of() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

# Бинарь ляжет в /usr/bin и будет исполняться от root, а gh-прокси в списке зеркал по устройству —
# MITM: сумма, взятая с того же зеркала, что и бинарь, не доказывает ничего (подменивший бинарь
# подменит и её). Поэтому сумму собираем со ВСЕХ зеркал и требуем, чтобы независимые источники
# сошлись. rc: 0 — сумма на stdout (пусто = не опубликована нигде), 2 — зеркала расходятся.
collect_sha() { # <asset>
	sum=""
	for base in $(mirrors); do
		t="$(mktemp "${TMPDIR:-/tmp}/mb-hysum.XXXXXX")" || continue
		s=""
		if mb_fetch "$base/$1.sha256" "$t" 2>/dev/null && [ -s "$t" ]; then
			s="$(awk '{print $1; exit}' "$t")"
		fi
		rm -f "$t"
		[ -n "$s" ] || continue
		[ -n "$sum" ] || { sum="$s"; continue; }
		[ "$sum" = "$s" ] || return 2
	done
	echo "$sum"
}

# HTML-страницу ошибки вместо бинаря ловим ДО сверки суммы: это отказ конкретного зеркала, и
# осмысленно идти к следующему, а не объявлять подмену.
check_elf() { # <file>
	[ -s "$1" ] || { echo "empty file"; return 1; }
	head -c 4 "$1" | grep -q "ELF" || { echo "not an ELF binary (mirror returned an error page?)"; return 1; }
	return 0
}

# Запуск — только ПОСЛЕ сверки суммы: до неё файл ничем не отличается от того, что подсунуло зеркало.
check_runs() { # <file>
	chmod 755 "$1" 2>/dev/null
	"$1" version >/dev/null 2>&1 || { echo "binary does not run on this device (wrong arch?)"; return 1; }
	return 0
}

cmd_install() {
	# Кнопка в UI нажимается повторно, пока идёт закачка. Без замка второй прогон качал бы те же
	# ~15МБ в тот же $DEST и своей ошибкой затирал бы «ok» первого. mkdir атомарен на overlay.
	if ! mkdir "$LOCK" 2>/dev/null; then
		echo "install is already running" >&2
		return 1
	fi
	trap 'rmdir "$LOCK" 2>/dev/null' EXIT INT TERM
	name="$(asset)" || {
		set_state "error: unsupported architecture $(uname -m)"
		echo "unsupported architecture: $(uname -m)" >&2
		return 1
	}
	set_state "updating"
	fdst="$(free_kb "$(dirname "$DEST")")"
	# ~15МБ бинарь + копия на время скачивания; на переполненном overlay mv оставил бы обрезанный файл
	if [ -n "$fdst" ] && [ "$fdst" -lt 40960 ]; then
		set_state "error: нужно ~40MB в $(dirname "$DEST"), свободно $(( fdst / 1024 ))MB"
		return 1
	fi
	last_err=""; rsum=""; sum_rc=0
	for base in $(mirrors); do
		url="$base/$name"
		tmp="$(mktemp "${TMPDIR:-/tmp}/mb-hysteria.XXXXXX")" || { set_state "error: mktemp failed"; return 1; }
		if ! mb_fetch "$url" "$tmp"; then last_err="unreachable"; rm -f "$tmp"; continue; fi
		if ! err="$(check_elf "$tmp")"; then last_err="$err"; rm -f "$tmp"; continue; fi
		# Сумма собирается один раз и только когда бинарь на руках: тянуть её раньше значит платить
		# запросами ко всем зеркалам даже там, где качать всё равно нечего.
		if [ -z "$rsum" ]; then rsum="$(collect_sha "$name")"; sum_rc=$?; fi
		# Нет суммы или источники расходятся -> не ставим ВООБЩЕ (следующее зеркало положения не
		# меняет): непроверяемый бинарь под root — цена выше, чем «второй протокол не заработал».
		if [ "$sum_rc" != 0 ] || [ -z "$rsum" ]; then
			last_err="nosum"; rm -f "$tmp"; break
		fi
		if [ "$rsum" != "$(sha_of "$tmp")" ]; then last_err="checksum"; rm -f "$tmp"; continue; fi
		if ! err="$(check_runs "$tmp")"; then last_err="$err"; rm -f "$tmp"; continue; fi
		if ! mv -f "$tmp" "$DEST"; then last_err="install move failed"; rm -f "$tmp"; continue; fi
		chmod 755 "$DEST"
		set_state "ok"
		echo "hysteria installed from $url"
		return 0
	done
	case "$last_err" in
		checksum) set_state "error: контрольная сумма не сошлась ни на одном зеркале" ;;
		nosum) if [ "$sum_rc" != 0 ]; then
				set_state "error: зеркала отдают разные контрольные суммы — установка отменена"
			else
				set_state "error: контрольная сумма не опубликована ни на одном зеркале — установка отменена"
			fi ;;
		unreachable|"") set_state "error: не скачать hysteria — все зеркала недоступны (нет интернета либо блокировка)" ;;
		*) set_state "error: $last_err" ;;
	esac
	return 1
}

cmd_remove() {
	rm -f "$DEST" "$CONF"
	set_state "idle"
	echo "hysteria removed"
}

# Строка состояния собирается из сообщений об ошибках (в них попадают пути и вывод зеркал), а её
# читает json() в rpcd: незакавыченная кавычка или бэкслеш дали бы битый JSON, и рантайм молча
# подменил бы его на {state:'idle'} — то есть настоящая причина отказа исчезла бы из UI ровно тогда,
# когда она нужна.
json_escape() { sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/[[:cntrl:]]//g'; }

cmd_status() {
	st="$(cat "$STATE" 2>/dev/null | json_escape || echo idle)"
	inst=false; ver=""
	if [ -x "$DEST" ]; then
		inst=true
		ver="$("$DEST" version 2>/dev/null | awk '/^Version:/{print $2; exit}' | json_escape)"
	fi
	printf '{"state":"%s","installed":%s,"version":"%s"}\n' "${st:-idle}" "$inst" "$ver"
}

case "${1:-}" in
	install) cmd_install ;;
	remove)  cmd_remove ;;
	status)  cmd_status ;;
	*) echo "usage: $0 {install|remove|status}" >&2; exit 2 ;;
esac
