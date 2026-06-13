#!/bin/sh
# Управление geo-базами Xray (geoip.dat/geosite.dat) с ВАЛИДАЦИЕЙ реальным xray
# перед установкой в asset-каталог. Команды:
#   geo.sh download              # скачать (URL из UCI geo.* или дефолт Loyalsoldier), провалидировать, установить
#   geo.sh install <which> <src> # провалидировать загруженный файл и установить (which: geoip|geosite)
#   geo.sh status                # JSON: updating/present/size/last_error
# Фоновый запуск (download) пишет состояние в STATE, чтобы UI поллил без ubus-таймаута.
set -u

DEST="${MB_GEO_DIR:-/usr/share/xray}"
STATE="/tmp/mb-geo.state"
DEFAULT_BASE="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download"

uci_get() { uci -q get "monkey-business.geo.$1" 2>/dev/null || echo ""; }
set_state() { echo "$1" >"$STATE"; }

fetch() { # fetch <url> <out>
	if command -v curl >/dev/null 2>&1; then curl -fsSL -m 120 -o "$2" "$1"
	elif command -v uclient-fetch >/dev/null 2>&1; then uclient-fetch -q -T 120 -O "$2" "$1"
	else wget -q -T 120 -O "$2" "$1"; fi
}

# validate <which> <file> -> 0 если xray грузит .dat
validate() {
	which="$1"; file="$2"
	[ -s "$file" ] || { echo "empty file"; return 1; }
	dir="/tmp/mb-geocheck"
	rm -rf "$dir"; mkdir -p "$dir"
	cp "$file" "$dir/$which.dat" || return 1
	if [ "$which" = "geoip" ]; then
		rule='"ip":["geoip:private"]'
	else
		rule='"domain":["geosite:private"]'
	fi
	cat >"$dir/test.json" <<EOF
{"inbounds":[{"port":10800,"protocol":"socks","settings":{}}],"outbounds":[{"protocol":"freedom"},{"tag":"blk","protocol":"blackhole"}],"routing":{"rules":[{"type":"field",$rule,"outboundTag":"blk"}]}}
EOF
	XRAY_LOCATION_ASSET="$dir" xray run -test -c "$dir/test.json" >/tmp/mb-geocheck.err 2>&1
	rc=$?
	rm -rf "$dir"
	if [ "$rc" != 0 ]; then
		line="$(grep -iE 'failed|error|invalid|panic' /tmp/mb-geocheck.err | head -1)"
		[ -n "$line" ] || line="invalid geo .dat (xray test failed)"
		echo "$which.dat rejected: $line"
		return 1
	fi
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
	t="/tmp/mb-sum.$$"
	if fetch "$1.sha256sum" "$t" 2>/dev/null && [ -s "$t" ]; then
		awk '{print $1; exit}' "$t"
	fi
	rm -f "$t"
}

cmd_download() {
	set_state "updating"
	base="${MB_GEO_BASE:-$DEFAULT_BASE}"
	gip="$(uci_get geoip_url)"; gst="$(uci_get geosite_url)"
	[ -n "$gip" ] || gip="$base/geoip.dat"
	[ -n "$gst" ] || gst="$base/geosite.dat"
	changed=0
	for pair in "geoip $gip" "geosite $gst"; do
		which="${pair%% *}"; url="${pair#* }"
		rsum="$(remote_sha "$url")"
		# свежая версия уже стоит -> пропустить скачивание
		if [ -n "$rsum" ] && [ -f "$DEST/$which.dat" ] && [ "$rsum" = "$(sha_of "$DEST/$which.dat")" ]; then
			echo "$which: up to date (sha256 match), skipped"
			continue
		fi
		tmp="/tmp/mb-$which.dl"
		if ! fetch "$url" "$tmp"; then set_state "error: download failed ($which)"; rm -f "$tmp"; return 1; fi
		# проверка целостности по контрольной сумме (если она доступна)
		if [ -n "$rsum" ] && [ "$rsum" != "$(sha_of "$tmp")" ]; then
			set_state "error: checksum mismatch ($which)"; rm -f "$tmp"; return 1
		fi
		if ! err="$(install_one "$which" "$tmp")"; then set_state "error: $err"; rm -f "$tmp"; return 1; fi
		changed=1
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
