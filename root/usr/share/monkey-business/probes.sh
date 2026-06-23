#!/bin/sh
# Сетевые пробы watchdog (чистый I/O, без состояния). Сорсится watchdog.sh.
# liveness — TLS-handshake через socks к иностранному IP; exit/direct — echo-IP сервисы.
# Цели LIVE_URLS обязаны быть proxied (foreign, НЕ в direct-листе); PROBE_URLS тоже через proxy.
set -u

SOCKS="${MB_WD_SOCKS:-127.0.0.1:10808}"
LIVE_URLS="${MB_WD_LIVE_URLS:-https://1.1.1.1 https://8.8.8.8}"
PROBE_URLS="${MB_WD_PROBE_URLS:-https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com}"
PROBE_TIMEOUT="${MB_WD_TIMEOUT:-10}"
LIVE_TIMEOUT="${MB_WD_LIVE_TIMEOUT:-6}"

extract_ip() { printf '%s' "${1:-}" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1; }

probe_via() {
	for u in $PROBE_URLS; do
		# shellcheck disable=SC2086
		ip=$(extract_ip "$(curl -s -4 $1 --max-time "$2" "$u" 2>/dev/null)")
		[ -n "$ip" ] && { printf '%s' "$ip"; return; }
	done
}

vpn_probe() { probe_via "-x socks5h://$SOCKS" "$1"; }
direct_probe() { probe_via "" "$PROBE_TIMEOUT"; }

live_probe() {
	for u in $LIVE_URLS; do
		curl -s -4 -o /dev/null -x "socks5h://$SOCKS" --max-time "$LIVE_TIMEOUT" "$u" 2>/dev/null && return 0
	done
	return 1
}
