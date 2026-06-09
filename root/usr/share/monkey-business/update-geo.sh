#!/bin/sh
# Скачивание geoip.dat/geosite.dat для Xray (asset dir /usr/share/xray).
# Источник: Loyalsoldier/v2ray-rules-dat (latest). Атомарно (download -> mv).
# Категории генератора подогнаны под этот набор (geoip:ru, geosite:category-ru/private).
set -u

DEST="${MB_GEO_DIR:-/usr/share/xray}"
BASE="${MB_GEO_BASE:-https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download}"

mkdir -p "$DEST" || { echo "cannot create $DEST" >&2; exit 1; }

fetch() {
	# fetch <url> <out>
	if command -v uclient-fetch >/dev/null 2>&1; then
		uclient-fetch -q -T 30 -O "$2" "$1"
	elif command -v curl >/dev/null 2>&1; then
		curl -fsSL -o "$2" "$1"
	elif command -v wget >/dev/null 2>&1; then
		wget -q -O "$2" "$1"
	else
		echo "no downloader (uclient-fetch/curl/wget)" >&2
		return 1
	fi
}

for f in geoip.dat geosite.dat; do
	tmp="$DEST/.$f.tmp"
	if ! fetch "$BASE/$f" "$tmp"; then
		echo "download failed: $f" >&2
		rm -f "$tmp"
		exit 1
	fi
	# .dat не должен быть пустым/HTML-ошибкой
	if [ ! -s "$tmp" ]; then
		echo "empty download: $f" >&2
		rm -f "$tmp"
		exit 1
	fi
	mv -f "$tmp" "$DEST/$f"
	echo "updated $DEST/$f ($(wc -c <"$DEST/$f") bytes)"
done

echo "geo databases ready in $DEST"
