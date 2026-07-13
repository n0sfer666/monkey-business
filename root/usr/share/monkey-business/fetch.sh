#!/bin/sh
# Общая загрузка файлов для geo.sh/ruset.sh. Публичный контракт: mb_fetch <url> <out> -> 0/1.
#
# Сначала напрямую, при провале — через socks самого xray. Трафик РОУТЕРА идёт мимо tproxy, поэтому
# упирается в блокировки провайдера (raw.githubusercontent.com у RU-ISP не открывается), хотя у
# LAN-клиентов тот же адрес работает через туннель. Без фолбэка ruset.sh не собирает RU-сет, и весь
# российский трафик уходит в туннель — ровно та «тормозящая локалка», от которой сет и спасает.
# Env: MB_FETCH_TIMEOUT(120) MB_FETCH_SOCKS(127.0.0.1:10808).

MB_FETCH_TIMEOUT="${MB_FETCH_TIMEOUT:-120}"
MB_FETCH_SOCKS="${MB_FETCH_SOCKS:-127.0.0.1:10808}"

mb_fetch_direct() { # <url> <out>
	if command -v curl >/dev/null 2>&1; then curl -fsSL -m "$MB_FETCH_TIMEOUT" -o "$2" "$1"
	elif command -v uclient-fetch >/dev/null 2>&1; then uclient-fetch -q -T "$MB_FETCH_TIMEOUT" -O "$2" "$1"
	else wget -q -T "$MB_FETCH_TIMEOUT" -O "$2" "$1"; fi
}

# socks поднимает только живой xray; без него фолбэк бессмысленен
mb_fetch_socks() { # <url> <out>
	command -v curl >/dev/null 2>&1 || return 1
	pidof xray >/dev/null 2>&1 || return 1
	curl -fsSL -m "$MB_FETCH_TIMEOUT" -x "socks5h://$MB_FETCH_SOCKS" -o "$2" "$1"
}

mb_fetch() { # <url> <out>
	mb_fetch_direct "$1" "$2" && return 0
	rm -f "$2" 2>/dev/null
	mb_fetch_socks "$1" "$2" || { rm -f "$2" 2>/dev/null; return 1; }
	echo "fetch: $1: direct failed, fetched via tunnel" >&2
	return 0
}
