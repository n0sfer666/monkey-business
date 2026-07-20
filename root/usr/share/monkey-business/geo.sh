#!/bin/sh
# Управление geo-базами Xray (geoip.dat/geosite.dat) с ВАЛИДАЦИЕЙ реальным xray
# перед установкой в asset-каталог. Команды:
#   geo.sh download              # скачать (URL из UCI geo.* или дефолт Loyalsoldier), провалидировать, установить
#   geo.sh install <which> <src> # провалидировать загруженный файл и установить (which: geoip|geosite)
#   geo.sh status                # JSON: updating/present/size/last_error
# Фоновый запуск (download) пишет состояние в STATE, чтобы UI поллил без ubus-таймаута.
set -u

DEST="${MB_GEO_DIR:-/usr/share/xray}"
STATE="${MB_GEO_STATE:-/tmp/mb-geo.state}"
# Зеркала как base-URL: к каждому добавляется /<which>.dat (+ .sha256sum). Перебор до первого, с
# которого реально скачалось. CDN-зеркала (jsDelivr) идут ПЕРВЫМИ — GitHub у многих RU-провайдеров
# заблокирован, а geo нужны ДО поднятия VPN (иначе тупик: нет geo -> нет direct-маршрутов -> нет
# туннеля -> нечем качать geo). GitHub оставлен последним фолбэком. Переопределяется через
# MB_GEO_MIRRORS (список через пробел) или UCI monkey-business.geo.mirrors.
DEFAULT_MIRRORS="https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release https://fastly.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release https://gcore.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release https://testingcf.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download"

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

# список зеркал: UCI -> env -> дефолт (все элементы через пробел)
mirrors() {
	m="$(uci_get mirrors)"; [ -n "$m" ] && { echo "$m"; return; }
	echo "${MB_GEO_MIRRORS:-$DEFAULT_MIRRORS}"
}

# candidates <which> -> URL-кандидаты (по одному в строке). Кастомный URL из UCI (полный) имеет
# приоритет и отключает перебор зеркал; иначе <base>/<which>.dat по каждому зеркалу по порядку.
candidates() {
	which="$1"; custom="$(uci_get "${which}_url")"
	if [ -n "$custom" ]; then echo "$custom"; return; fi
	for base in $(mirrors); do echo "$base/$which.dat"; done
}

# свободные КБ на ФС, где лежит путь (busybox df -k). пусто, если df недоступен/путь не резолвится.
free_kb() { df -k "$1" 2>/dev/null | awk 'NR>1{print $4; exit}'; }

# check_space <which> <bytes> -> 0 если места хватает, иначе печатает причину (RU) и возвращает 1.
# temp-ФС нужно ~2×размер (качаем + копия для валидации xray), DEST-ФС — 1×. Запас 2МБ на накладные.
# Неизвестное свободное место (df молчит) не блокирует — лучше попробовать, чем врать про нехватку.
check_space() {
	which="$1"; bytes="$2"; tdir="${TMPDIR:-/tmp}"
	tmp_need_kb=$(( bytes * 2 / 1024 + 2048 )); dest_need_kb=$(( bytes / 1024 + 2048 ))
	ftmp="$(free_kb "$tdir")"; fdst="$(free_kb "$DEST")"
	if [ -n "$ftmp" ] && [ "$ftmp" -lt "$tmp_need_kb" ]; then
		echo "no space: $which нужно ~$(( tmp_need_kb / 1024 ))MB в $tdir (скачивание+валидация), свободно $(( ftmp / 1024 ))MB"
		return 1
	fi
	if [ -n "$fdst" ] && [ "$fdst" -lt "$dest_need_kb" ]; then
		echo "no space: $which нужно ~$(( dest_need_kb / 1024 ))MB в $DEST, свободно $(( fdst / 1024 ))MB"
		return 1
	fi
	return 0
}

# validate <which> <file> -> 0 если xray грузит .dat
validate() {
	which="$1"; file="$2"
	command -v xray >/dev/null 2>&1 || { echo "xray not installed"; return 1; }
	[ -s "$file" ] || { echo "empty file"; return 1; }
	# уникальный каталог на вызов: без клоббера/TOCTOU при параллельных validate
	dir="$(mktemp -d "${TMPDIR:-/tmp}/mb-geocheck.XXXXXX")" || { echo "mktemp failed"; return 1; }
	cp "$file" "$dir/$which.dat" || { rm -rf "$dir"; return 1; }
	if [ "$which" = "geoip" ]; then
		rule='"ip":["geoip:private"]'
	else
		rule='"domain":["geosite:private"]'
	fi
	cat >"$dir/test.json" <<EOF
{"inbounds":[{"port":10800,"protocol":"socks","settings":{}}],"outbounds":[{"protocol":"freedom"},{"tag":"blk","protocol":"blackhole"}],"routing":{"rules":[{"type":"field",$rule,"outboundTag":"blk"}]}}
EOF
	XRAY_LOCATION_ASSET="$dir" xray run -test -c "$dir/test.json" >"$dir/err" 2>&1
	rc=$?
	if [ "$rc" != 0 ]; then
		# НЕ подставлять заглушку "invalid .dat": xray падает и по причинам, не связанным с файлом
		# (нет бинарника, нет прав, нет места) -> ложное обвинение файла уводит диагностику в сторону.
		line="$(grep -iE 'failed|error|invalid|panic' "$dir/err" | head -1)"
		[ -n "$line" ] || line="$(head -1 "$dir/err" 2>/dev/null)"
		[ -n "$line" ] || line="xray -test exited with code $rc, no output"
		rm -rf "$dir"
		echo "$which.dat rejected: $line"
		return 1
	fi
	rm -rf "$dir"
	return 0
}

install_one() { # install_one <which> <src>
	which="$1"; src="$2"
	msg="$(validate "$which" "$src")" || { echo "$msg"; return 1; }
	mkdir -p "$DEST"
	mv -f "$src" "$DEST/$which.dat" || { echo "install move failed"; return 1; }
	return 0
}

# sha256 первого поля (для .sha256sum-файла или локального файла)
sha_of() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }
remote_sha() { # remote_sha <dat_url> -> печатает hash или пусто
	t="$(mktemp "${TMPDIR:-/tmp}/mb-sum.XXXXXX")" || return 0
	if mb_fetch "$1.sha256sum" "$t" 2>/dev/null && [ -s "$t" ]; then
		awk '{print $1; exit}' "$t"
	fi
	rm -f "$t"
}

cmd_download() {
	if ! command -v xray >/dev/null 2>&1; then
		set_state "error: xray not installed (apk add xray-core)"
		echo "xray not installed — cannot validate geo databases" >&2
		return 1
	fi
	set_state "updating"
	mkdir -p "$DEST" 2>/dev/null
	changed=0
	for which in geoip geosite; do
		done_one=0; last_err=""
		# перебор зеркал: первое, с которого файл скачался, провалидировался xray и (если есть)
		# сошёлся по sha256 — побеждает. Недоступное/битое зеркало -> следующий кандидат.
		for url in $(candidates "$which"); do
			rsum="$(remote_sha "$url")"
			# свежая версия уже стоит -> пропустить скачивание (sha берётся с этого же зеркала)
			if [ -n "$rsum" ] && [ -f "$DEST/$which.dat" ] && [ "$rsum" = "$(sha_of "$DEST/$which.dat")" ]; then
				echo "$which: up to date (sha256 match), skipped"; done_one=1; break
			fi
			# превентивная проверка места: если размер узнали и его не хватает — это НЕ про зеркала,
			# другой хост не поможет, падаем сразу. Размер неизвестен -> не блокируем.
			sz="$(mb_remote_size "$url")"
			if [ -n "$sz" ] && ! reason="$(check_space "$which" "$sz")"; then
				set_state "error: $reason"; return 1
			fi
			tmp="$(mktemp "${TMPDIR:-/tmp}/mb-$which.dl.XXXXXX")" || { set_state "error: mktemp failed ($which)"; return 1; }
			if ! mb_fetch "$url" "$tmp"; then last_err="unreachable"; rm -f "$tmp"; continue; fi
			if [ -n "$rsum" ] && [ "$rsum" != "$(sha_of "$tmp")" ]; then last_err="checksum"; rm -f "$tmp"; continue; fi
			if ! err="$(install_one "$which" "$tmp")"; then last_err="$err"; rm -f "$tmp"; continue; fi
			echo "$which: fetched from $url"; changed=1; done_one=1; break
		done
		if [ "$done_one" = 0 ]; then
			case "$last_err" in
				checksum) set_state "error: $which — контрольная сумма не сошлась ни на одном зеркале" ;;
				unreachable|"") set_state "error: не скачать $which — все зеркала недоступны (нет интернета либо блокировка)" ;;
				*) set_state "error: $which — $last_err" ;;
			esac
			return 1
		fi
	done
	if [ "$changed" = 0 ]; then
		set_state "unchanged"
		echo "geo databases already up to date"
	else
		set_state "ok"
		echo "geo databases ready in $DEST"
	fi
}

cmd_install() { # install <which> <src>
	which="$1"; src="${2:-}"
	[ "$which" = geoip ] || [ "$which" = geosite ] || { echo "bad which"; exit 2; }
	[ -f "$src" ] || { echo "no source file"; exit 2; }
	set_state "updating"
	if ! err="$(install_one "$which" "$src")"; then set_state "error: $err"; echo "$err" >&2; exit 1; fi
	set_state "ok"
	echo "installed $which"
}

cmd_status() {
	st="$(cat "$STATE" 2>/dev/null || echo idle)"
	gip=0; gst=0
	[ -f "$DEST/geoip.dat" ] && gip="$(wc -c <"$DEST/geoip.dat")"
	[ -f "$DEST/geosite.dat" ] && gst="$(wc -c <"$DEST/geosite.dat")"
	printf '{"state":"%s","geoip":%s,"geosite":%s}\n' "$st" "$gip" "$gst"
}

case "${1:-}" in
	download) shift; cmd_download "$@" ;;
	install)  shift; cmd_install "$@" ;;
	status)   cmd_status ;;
	*) echo "usage: $0 {download|install <which> <src>|status}" >&2; exit 2 ;;
esac
