#!/bin/sh
# Общая загрузка файлов для geo.sh/ruset.sh. Публичный контракт: mb_fetch <url> <out> -> 0/1.
#
# Сначала напрямую, при провале — через socks самого xray. Трафик РОУТЕРА идёт мимо tproxy, поэтому
# упирается в блокировки провайдера (raw.githubusercontent.com у RU-ISP не открывается), хотя у
# LAN-клиентов тот же адрес работает через туннель. Без фолбэка ruset.sh не собирает RU-сет, и весь
# российский трафик уходит в туннель — ровно та «тормозящая локалка», от которой сет и спасает.
# Env: MB_FETCH_TIMEOUT(120) MB_FETCH_SOCKS(127.0.0.1:10808) MB_FETCH_XRAY_MATCH.

MB_FETCH_TIMEOUT="${MB_FETCH_TIMEOUT:-120}"
# socks 10808 поднимает только БОЕВОЙ xray -> матчим его cmdline, а не любой процесс `xray`
# (эфемерная проба failover слушает 10809 и socks-фолбэк с ней не работает).
MB_FETCH_XRAY_MATCH="${MB_FETCH_XRAY_MATCH:-xray run -c /etc/monkey-business/xray.json}"
# без pgrep (урезанный busybox) деградируем до pidof: грубее, но лучше отказа от socks-фолбэка
if command -v pgrep >/dev/null 2>&1; then
	mb_xray_up() { pgrep -f "$MB_FETCH_XRAY_MATCH" >/dev/null 2>&1; }
else
	mb_xray_up() { pidof xray >/dev/null 2>&1; }
fi
# короткий таймаут установления соединения: перебор зеркал не должен ждать 120с на мёртвом хосте
MB_FETCH_CONNECT="${MB_FETCH_CONNECT:-10}"
# Мёртвому зеркалу не обязательно отказывать в соединении: gh-прокси принимают TCP и дальше отдают
# ~140 байт/с — connect-timeout такое не ловит, и перебор сжигал по целому MB_FETCH_TIMEOUT на
# каждом (живая установка hysteria: 8м46с, из них ~8 минут — ожидание мёртвых зеркал). Средняя
# скорость ниже MIN_RATE дольше STALL секунд -> бросаем зеркало и идём к следующему. Порог низкий
# намеренно: на нём 21МБ качались бы часами, то есть отсекается заведомо безнадёжное, а не просто
# медленный канал.
MB_FETCH_MIN_RATE="${MB_FETCH_MIN_RATE:-1024}"
MB_FETCH_STALL="${MB_FETCH_STALL:-20}"
MB_FETCH_SOCKS="${MB_FETCH_SOCKS:-127.0.0.1:10808}"

# Лимиты одним местом. Переменные разворачиваются в момент вызова, а не в константе: hysteria.sh
# временно урезает MB_FETCH_TIMEOUT на мелких файлах, и константа этого бы не увидела.
mb_curl() { # <curl-args...>
	curl -fsSL --connect-timeout "$MB_FETCH_CONNECT" -m "$MB_FETCH_TIMEOUT" \
		--speed-limit "$MB_FETCH_MIN_RATE" --speed-time "$MB_FETCH_STALL" "$@"
}

mb_fetch_direct() { # <url> <out>
	# только curl умеет РАЗДЕЛЬНО connect-timeout (быстро отсечь мёртвое зеркало), порог скорости и
	# общий лимит; у uclient-fetch/wget -T = общий таймаут операции, поэтому им оставляем полный
	# MB_FETCH_TIMEOUT, иначе крупные списки (ruset.sh) рвались бы на медленном канале.
	if command -v curl >/dev/null 2>&1; then mb_curl -o "$2" "$1"
	elif command -v uclient-fetch >/dev/null 2>&1; then uclient-fetch -q -T "$MB_FETCH_TIMEOUT" -O "$2" "$1"
	else wget -q -T "$MB_FETCH_TIMEOUT" -O "$2" "$1"; fi
}

# socks поднимает только живой xray; без него фолбэк бессмысленен
mb_fetch_socks() { # <url> <out>
	command -v curl >/dev/null 2>&1 || return 1
	mb_xray_up || return 1
	mb_curl -x "socks5h://$MB_FETCH_SOCKS" -o "$2" "$1"
}

mb_fetch() { # <url> <out>
	mb_fetch_direct "$1" "$2" && return 0
	rm -f "$2" 2>/dev/null
	mb_fetch_socks "$1" "$2" || { rm -f "$2" 2>/dev/null; return 1; }
	echo "fetch: $1: direct failed, fetched via tunnel" >&2
	return 0
}

# размер файла по URL в байтах (Content-Length из HEAD), напрямую -> через socks. Печатает число
# или пусто, если узнать не вышло (нет сети/curl/HEAD запрещён). Никогда не валит вызывающего:
# нужен для превентивной проверки места, но его отсутствие не должно ломать саму загрузку.
mb_content_length() { # reads HTTP headers on stdin -> печатает байты или пусто
	# tolower(), а НЕ IGNORECASE: последнее — расширение gawk, busybox/BWK awk его игнорируют, и
	# Title-Case заголовок "Content-Length:" (HTTP/1.1) не матчился бы -> precheck молча мёртв.
	awk 'tolower($0) ~ /^content-length:/ { v=$2; gsub(/[^0-9]/,"",v); if(v!="") n=v } END{ if(n!="") print n }'
}
mb_remote_size() { # <url> -> байты или пусто
	command -v curl >/dev/null 2>&1 || return 0
	_sz="$(mb_curl -I "$1" 2>/dev/null | mb_content_length)"
	if [ -z "$_sz" ] && mb_xray_up; then
		_sz="$(mb_curl -x "socks5h://$MB_FETCH_SOCKS" -I "$1" 2>/dev/null | mb_content_length)"
	fi
	[ -n "$_sz" ] && printf '%s' "$_sz"
	return 0
}
