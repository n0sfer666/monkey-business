#!/bin/sh
set -eu

CACHE="${MB_GEO_CACHE:?MB_GEO_CACHE не задан, запускай через make dev}"
R2S="${MB_GEO_R2S:-root@192.168.1.1}"
GEO_SH=root/usr/share/monkey-business/geo.sh
MIRRORS="${MB_GEO_MIRRORS:-$(sed -n 's/^DEFAULT_MIRRORS="\(.*\)"$/\1/p' "$GEO_SH")}"

[ -n "$MIRRORS" ] || echo "!! geo: не нашёл DEFAULT_MIRRORS в $GEO_SH (формат поменялся?), сверки с источником не будет" >&2
mkdir -p "$CACHE"

sha_of() { shasum -a 256 "$1" | cut -d' ' -f1; }

seal() { sha_of "$CACHE/$1.dat" >"$CACHE/$1.dat.sha256"; }

from_r2s() {
	ls "$CACHE"/geoip.dat "$CACHE"/geosite.dat >/dev/null 2>&1 && return 0
	echo ">> geo: кэш пуст, беру базы с $R2S"
	for which in geoip geosite; do
		[ -s "$CACHE/$which.dat" ] && continue
		if scp -q -O -o BatchMode=yes -o ConnectTimeout=5 "$R2S:/usr/share/xray/$which.dat" "$CACHE/$which.dat.part" 2>/dev/null; then
			mv -f "$CACHE/$which.dat.part" "$CACHE/$which.dat"
		else
			rm -f "$CACHE/$which.dat.part"
			echo "   $which: $R2S недоступен, пойду на зеркала"
		fi
	done
}

refresh() {
	which="$1"
	file="$CACHE/$which.dat"
	for base in $MIRRORS; do
		want=$(curl -fsSL --connect-timeout 3 -m 8 "$base/$which.dat.sha256sum" 2>/dev/null | cut -d' ' -f1)
		case "$want" in *[!0-9a-f]* | '') continue ;; esac
		[ ${#want} -eq 64 ] || continue
		if [ -s "$file" ] && [ "$(sha_of "$file")" = "$want" ]; then
			echo ">> geo: $which свежий (sha256 совпал)"
			return 0
		fi
		echo ">> geo: $which устарел или отсутствует, качаю с $base"
		if ! curl -fsSL --connect-timeout 5 --speed-limit 10240 --speed-time 30 -m 900 -o "$file.part" "$base/$which.dat"; then
			rm -f "$file.part"
			[ -s "$file" ] && break
			echo "   $which: зеркало не отдало файл, следующее"
			continue
		fi
		if [ "$(sha_of "$file.part")" = "$want" ]; then
			mv -f "$file.part" "$file"
			return 0
		fi
		rm -f "$file.part"
		echo "   $which: сумма не сошлась с $base, следующее"
	done
	if [ -s "$file" ]; then
		echo "!! geo: $which не обновлён с источника, беру кэш как есть" >&2
		return 0
	fi
	echo "!! geo: $which нет ни в кэше, ни на зеркалах" >&2
	return 1
}

from_r2s
rc=0
for which in geoip geosite; do
	rm -f "$CACHE/$which.dat.sha256"
	refresh "$which" || rc=1
	[ -s "$CACHE/$which.dat" ] && seal "$which"
done
exit "$rc"
