#!/bin/sh
# Установка клиента hysteria2 (один статический бинарь) с перебором зеркал и валидацией.
#   hysteria.sh install   # скачать под текущую архитектуру, проверить, положить в /usr/bin/hysteria
#   hysteria.sh status    # JSON: installed/version/state
#   hysteria.sh remove    # снять бинарь и конфиг клиента
#
# Бинарь не пакуем в ipk и не тянем из apk: в feeds ImmortalWrt hysteria нет, а вшивать 15МБ в пакет
# ради второго протокола дорого. Логика та же, что у geo.sh: зеркала -> скачать -> sha256 -> проверить
# запуском -> атомарно поставить. Отличие от geo.sh: там данные, тут исполняемое под root, поэтому
# сумма обязательна и без неё установка отменяется — сбор суммы и голосование по ней в hysum.sh.
set -u

DEST="${MB_HY_BIN:-/usr/bin/hysteria}"
CONF="${MB_HY_CONF:-/etc/monkey-business/hysteria.json}"
STATE="${MB_HY_STATE:-/tmp/mb-hysteria.state}"
LOCK="${MB_HY_LOCK:-/tmp/mb-hysteria.lock}"
# Суммы апстрим публикует ОДНИМ файлом на релиз, строкой на ассет; отдельных <asset>.sha256 у него
# нет (404). За ними скрипт и ходил — и отменял установку «сумма не опубликована» на каждом прогоне.
HASHES="${MB_HY_HASHES:-hashes.txt}"
# Файл сумм — пара килобайт. Ждать на нём столько же, сколько на 20МБ бинаре, значит держать
# человека у «installing…» лишние минуты на каждом мёртвом зеркале.
SUM_TIMEOUT="${MB_HY_SUM_TIMEOUT:-30}"
# У бинаря лимит наоборот СВОЙ и большой: 21МБ не влезают в общие 120с ни на одном реальном канале
# медленнее ~170КБ/с — установка отменялась бы с «все зеркала недоступны» на исправной сети. Мёртвые
# зеркала отсекает не этот лимит, а порог скорости в fetch.sh.
BIN_TIMEOUT="${MB_HY_BIN_TIMEOUT:-900}"
# Возраст замка, после которого он считается брошенным (kill -9, ребут посреди закачки).
LOCK_STALE="${MB_HY_LOCK_STALE:-900}"
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
# hysum.sh — наш модуль, лежит рядом со скриптом (MB_LIB_DIR подменяют тесты только для fetch.sh)
SELF_DIR="$(dirname "$0")"
if [ -r "$SELF_DIR/hysum.sh" ]; then
	# shellcheck source-path=SCRIPTDIR source=hysum.sh
	. "$SELF_DIR/hysum.sh"
else
	collect_sha() { echo "hysum.sh not found in $SELF_DIR" >&2; return 4; }
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

# Кнопка в UI нажимается повторно, пока идёт закачка. Без замка второй прогон качал бы те же ~20МБ в
# тот же $DEST и своей ошибкой затирал бы «ok» первого. mkdir атомарен на overlay.
#
# Но каталог переживает kill -9 и ребут посреди закачки, и тогда кнопка отказывала бы НАВСЕГДА
# («install is already running»), лечилось бы только руками через ssh. Возраст каталога и есть
# возраст попытки — тот же приём, что у watchdog.sh с его брошенным замком.
take_lock() {
	mkdir "$LOCK" 2>/dev/null && return 0
	born="$(stat -c %Y "$LOCK" 2>/dev/null)" || return 1
	[ -n "$born" ] || return 1
	[ "$(( $(date +%s) - born ))" -gt "$LOCK_STALE" ] || return 1
	rmdir "$LOCK" 2>/dev/null
	mkdir "$LOCK" 2>/dev/null
}

cmd_install() {
	if ! take_lock; then
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
	# Сумма собирается ПЕРВОЙ. Без неё установка отменяется в любом случае (непроверяемый бинарь под
	# root — цена выше, чем «второй протокол не заработал»), а бинарь — 20МБ, которые на gh-прокси
	# качаются минутами: при обратном порядке человек ждал у «installing…» ровно за тем, чтобы эти
	# мегабайты выбросили.
	rsum="$(collect_sha "$name")"; sum_rc=$?
	case "$sum_rc" in
		0) ;;
		2) set_state "error: зеркала отдают разные контрольные суммы — установка отменена"; return 1 ;;
		3) set_state "error: сумму подтвердило меньше $MIN_VOTES зеркал — установка отменена (порог MB_HY_MIN_VOTES)"; return 1 ;;
		*) set_state "error: не удалось собрать контрольную сумму — установка отменена"; return 1 ;;
	esac
	if [ -z "$rsum" ]; then
		set_state "error: контрольная сумма не опубликована ни на одном зеркале — установка отменена"
		return 1
	fi
	last_err=""
	for base in $(mirrors); do
		url="$base/$name"
		tmp="$(mktemp "${TMPDIR:-/tmp}/mb-hysteria.XXXXXX")" || { set_state "error: mktemp failed"; return 1; }
		if ! fetch_timed "$BIN_TIMEOUT" "$url" "$tmp"; then last_err="unreachable"; rm -f "$tmp"; continue; fi
		if ! err="$(check_elf "$tmp")"; then last_err="$err"; rm -f "$tmp"; continue; fi
		if [ "$rsum" != "$(sha_of "$tmp")" ]; then last_err="checksum"; rm -f "$tmp"; continue; fi
		if ! err="$(check_runs "$tmp")"; then last_err="$err"; rm -f "$tmp"; continue; fi
		# $tmp лежит в tmpfs, а $DEST в overlay: mv между ФС — это копирование с последующим unlink,
		# и обрыв на нём (переполнение, питание) оставил бы в /usr/bin обрезанный файл с exec-битом,
		# который init поднял бы как рабочий клиент. Копируем рядом с целью и переименовываем уже в
		# пределах одной ФС — вот это переименование атомарно.
		if ! cp "$tmp" "$DEST.new" 2>/dev/null; then
			last_err="install copy failed"; rm -f "$tmp" "$DEST.new"; continue
		fi
		rm -f "$tmp"
		sync 2>/dev/null
		chmod 755 "$DEST.new"
		if ! mv -f "$DEST.new" "$DEST"; then last_err="install move failed"; rm -f "$DEST.new"; continue; fi
		set_state "ok"
		echo "hysteria installed from $url"
		return 0
	done
	case "$last_err" in
		checksum) set_state "error: контрольная сумма не сошлась ни на одном зеркале" ;;
		unreachable|"") set_state "error: не скачать hysteria — ни одно зеркало не отдало бинарь (нет интернета, блокировка либо канал медленнее порога)" ;;
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
