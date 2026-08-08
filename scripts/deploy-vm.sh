#!/bin/sh
# Раскладка проекта по реальным путям в dev-VM (или на устройстве) + рантайм-зависимости
# + перезапуск rpcd + проверка, что ubus-объект поднялся.
#
# Окружение:
#   MB_VM_SSH_PORT (2222)  MB_VM_SSH_HOST (root@localhost)
#   MB_VM_SSH_PASS — пароль для неинтерактивного входа (нужен sshpass). Пусто => спросит пароль.
#   MB_HTTP_PORT (8090) — порт LuCI для подсказки (актуален для localhost/dev-VM с пробросом QEMU).
#   MB_LUCI_URL — переопределить итоговую ссылку LuCI явно (иначе выводится из MB_VM_SSH_HOST).
set -eu

PORT="${MB_VM_SSH_PORT:-2222}"
HOST="${MB_VM_SSH_HOST:-root@localhost}"
PASS="${MB_VM_SSH_PASS:-}"
HTTP_PORT="${MB_HTTP_PORT:-8090}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

command -v ssh >/dev/null 2>&1 || { echo "ssh required" >&2; exit 1; }

SSH="ssh"
SCP="scp"
if [ -n "$PASS" ]; then
	if command -v sshpass >/dev/null 2>&1; then
		# -e: пароль из env SSHPASS, не из argv (иначе виден в `ps` другим пользователям)
		SSHPASS="$PASS"; export SSHPASS
		SSH="sshpass -e ssh"
		SCP="sshpass -e scp"
	else
		echo "warn: MB_VM_SSH_PASS задан, но sshpass не найден — будет интерактивный ввод" >&2
	fi
fi

# раскрываются в удалённую shell-строку под root -> допускаем только 0/1 (без инъекции)
RESPAWN="${MB_UBUS_RESPAWN:-0}"
case "$RESPAWN" in 0|1) ;; *) RESPAWN=0 ;; esac
ALLOW_MISSING="${MB_ALLOW_MISSING:-0}"
case "$ALLOW_MISSING" in 0|1) ;; *) ALLOW_MISSING=0 ;; esac

stage=$(mktemp -d)
tarball=$(mktemp)
cleanup() { rm -rf "$stage" "$tarball"; }
trap cleanup EXIT

echo ">> assembling install layout"

# портируемо (BSD install на macOS не знает -D): mkdir -p + cp
cpf() { mkdir -p "$(dirname "$2")"; cp "$1" "$2"; }

# rpcd-плагин + библиотека (src/ -> lib/monkey-business/, чтобы резолвились импорты плагина)
cpf root/usr/share/rpcd/ucode/monkey-business.uc "$stage/usr/share/rpcd/ucode/monkey-business.uc"
mkdir -p "$stage/usr/share/rpcd/ucode/lib/monkey-business"
cp -R src/. "$stage/usr/share/rpcd/ucode/lib/monkey-business/"

# UCI-конфиг + procd init
cpf root/etc/config/monkey-business "$stage/etc/config/monkey-business"
cpf root/etc/init.d/monkey-business "$stage/etc/init.d/monkey-business"
chmod 755 "$stage/etc/init.d/monkey-business"

# firewall-скрипты + geo-апдейтер
mkdir -p "$stage/usr/share/monkey-business/firewall"
cp scripts/firewall/apply.sh scripts/firewall/flush.sh "$stage/usr/share/monkey-business/firewall/"
chmod 755 "$stage/usr/share/monkey-business/firewall/"*.sh
cpf root/usr/share/monkey-business/fetch.sh "$stage/usr/share/monkey-business/fetch.sh"
chmod 644 "$stage/usr/share/monkey-business/fetch.sh"
cpf root/usr/share/monkey-business/geo.sh "$stage/usr/share/monkey-business/geo.sh"
chmod 755 "$stage/usr/share/monkey-business/geo.sh"
cpf root/usr/share/monkey-business/ruset.sh "$stage/usr/share/monkey-business/ruset.sh"
chmod 755 "$stage/usr/share/monkey-business/ruset.sh"
cpf root/usr/share/monkey-business/hysteria.sh "$stage/usr/share/monkey-business/hysteria.sh"
chmod 755 "$stage/usr/share/monkey-business/hysteria.sh"
cpf root/usr/share/monkey-business/hysum.sh "$stage/usr/share/monkey-business/hysum.sh"
chmod 644 "$stage/usr/share/monkey-business/hysum.sh"
# Библиотеки идут ПЕРЕД watchdog.sh: он сорсит их все, а cron тикает и во время заливки —
# новый watchdog рядом со старым набором библиотек падал бы молча.
# Самостоятельно не исполняются -> 644.
cpf root/usr/share/monkey-business/probes.sh "$stage/usr/share/monkey-business/probes.sh"
chmod 644 "$stage/usr/share/monkey-business/probes.sh"
cpf root/usr/share/monkey-business/recovery.sh "$stage/usr/share/monkey-business/recovery.sh"
chmod 644 "$stage/usr/share/monkey-business/recovery.sh"
cpf root/usr/share/monkey-business/phases.sh "$stage/usr/share/monkey-business/phases.sh"
chmod 644 "$stage/usr/share/monkey-business/phases.sh"
cpf root/usr/share/monkey-business/watchdog.sh "$stage/usr/share/monkey-business/watchdog.sh"
chmod 755 "$stage/usr/share/monkey-business/watchdog.sh"
cpf root/usr/share/monkey-business/boothealth.sh "$stage/usr/share/monkey-business/boothealth.sh"
chmod 755 "$stage/usr/share/monkey-business/boothealth.sh"
cpf root/usr/share/monkey-business/nicwatch.sh "$stage/usr/share/monkey-business/nicwatch.sh"
chmod 755 "$stage/usr/share/monkey-business/nicwatch.sh"
cpf root/usr/share/monkey-business/nicfw.sh "$stage/usr/share/monkey-business/nicfw.sh"
chmod 755 "$stage/usr/share/monkey-business/nicfw.sh"
cpf root/usr/share/monkey-business/subupdate.sh "$stage/usr/share/monkey-business/subupdate.sh"
chmod 755 "$stage/usr/share/monkey-business/subupdate.sh"
cpf root/usr/share/monkey-business/firmware/rtl8153b-2.fw \
	"$stage/usr/share/monkey-business/firmware/rtl8153b-2.fw"
chmod 644 "$stage/usr/share/monkey-business/firmware/rtl8153b-2.fw"
cpf root/etc/init.d/mb-boothealth "$stage/etc/init.d/mb-boothealth"
chmod 755 "$stage/etc/init.d/mb-boothealth"

# LuCI views + menu + acl
mkdir -p "$stage/www/luci-static/resources/view/monkey-business"
cp luci/htdocs/luci-static/resources/view/monkey-business/*.js \
	"$stage/www/luci-static/resources/view/monkey-business/"
cpf luci/root/usr/share/luci/menu.d/luci-app-monkey-business.json \
	"$stage/usr/share/luci/menu.d/luci-app-monkey-business.json"
cpf luci/root/usr/share/rpcd/acl.d/luci-app-monkey-business.json \
	"$stage/usr/share/rpcd/acl.d/luci-app-monkey-business.json"

# COPYFILE_DISABLE=1: macOS tar иначе кладёт AppleDouble-файлы '._*' (resource forks).
# rpcd-mod-ucode пытается компилировать '._monkey-business.uc' -> syntax error и может подвесить
# ubusd при рестарте. Плюс исключаем .DS_Store.
#
# В архиве НЕ должно быть записи './': mktemp -d создаёт корень стейджа с 0700 и локальным uid,
# а `tar -C /` на той стороне применил бы это к САМОМУ '/'. Корень 0700 root:501 переживает ребут,
# и любой демон, сбрасывающий привилегии (dnsmasq -> DHCP/DNS для LAN), перестаёт проходить по
# пути — роутер поднимается «без сети». Поэтому архивируем верхние каталоги поимённо, а список
# сверяем со стейджем, чтобы новый top-level каталог не потерялся молча.
chmod 755 "$stage"
for top in "$stage"/*; do
	case "${top##*/}" in
		etc|usr|www) ;;
		*) echo "!! неожиданный каталог в стейдже: ${top##*/} — добавь его в tar" >&2; exit 1 ;;
	esac
done
COPYFILE_DISABLE=1 tar --exclude '.DS_Store' --exclude '._*' -C "$stage" -czf "$tarball" ./etc ./usr ./www

echo ">> copying to $HOST:$PORT"
# shellcheck disable=SC2086
$SCP -O $SSH_OPTS -P "$PORT" "$tarball" "$HOST:/tmp/mb-deploy.tgz"

echo ">> installing files + runtime deps + reloading rpcd"
# MB_RESPAWN передаётся в удалённый шелл (значение раскрывается ЛОКАЛЬНО), сам скрипт — через
# stdin-heredoc <<'REMOTE' (без локального раскрытия $ внутри).
# shellcheck disable=SC2086
$SSH $SSH_OPTS -p "$PORT" "$HOST" "MB_RESPAWN='$RESPAWN' MB_ALLOW_MISSING='$ALLOW_MISSING' sh -s" <<'REMOTE'
	set -e
	# сохранить пользовательский UCI-конфиг (url/серверы/выбор) между деплоями — как conffile
	[ -f /etc/config/monkey-business ] && cp /etc/config/monkey-business /tmp/mb-cfg.keep
	tar -C / -xzf /tmp/mb-deploy.tgz
	[ -f /tmp/mb-cfg.keep ] && mv /tmp/mb-cfg.keep /etc/config/monkey-business
	# подчистить возможные macOS AppleDouble-остатки (BusyBox find без -delete, поэтому rm по glob)
	rm -f /usr/share/rpcd/ucode/._* /usr/share/rpcd/ucode/lib/monkey-business/._* 2>/dev/null || true
	# macOS tar сохраняет локальные uid/gid и режим НЕ только на наших файлах, но и на
	# каталогах-контейнерах, которые он создаёт по пути — включая корневой './' -> '/'.
	# Эти каталоги общесистемные, их нужно вернуть в 0755 root:root безусловно, иначе
	# после ребута демоны без привилегий не пройдут по пути и роутер встанет без LAN.
	for d in / /etc /etc/init.d /etc/config /usr /usr/bin /usr/share \
	         /usr/share/luci /usr/share/luci/menu.d \
	         /usr/share/rpcd /usr/share/rpcd/ucode /usr/share/rpcd/ucode/lib /usr/share/rpcd/acl.d \
	         /www /www/luci-static /www/luci-static/resources /www/luci-static/resources/view; do
		[ -d "$d" ] || continue
		chown root:root "$d" 2>/dev/null || true
		chmod 755 "$d" 2>/dev/null || true
	done

	# наши собственные пути — рекурсивно
	for d in /usr/share/rpcd/ucode/monkey-business.uc /usr/share/rpcd/ucode/lib/monkey-business \
	         /etc/config/monkey-business /etc/init.d/monkey-business /etc/init.d/mb-boothealth \
	         /usr/share/monkey-business \
	         /www/luci-static/resources/view/monkey-business \
	         /usr/share/luci/menu.d/luci-app-monkey-business.json \
	         /usr/share/rpcd/acl.d/luci-app-monkey-business.json; do
		chown -R root:root "$d" 2>/dev/null || true
	done
	chmod 644 /usr/share/rpcd/ucode/monkey-business.uc
	chmod +x /etc/init.d/monkey-business /etc/init.d/mb-boothealth \
		/usr/share/monkey-business/firewall/*.sh \
		/usr/share/monkey-business/watchdog.sh /usr/share/monkey-business/boothealth.sh \
		/usr/share/monkey-business/nicwatch.sh /usr/share/monkey-business/nicfw.sh \
		/usr/share/monkey-business/subupdate.sh
	rm -f /tmp/mb-deploy.tgz /tmp/luci-indexcache* 2>/dev/null || true
	# распакованное должно дойти до карты ДО рестартов ниже: если rpcd подвесит ubusd и роутер
	# уедет в жёсткий сброс, недописанные файлы останутся обрезанными в журнале ext4.
	sync

	# boot-resilience: ранний init-хук (детект unclean/ro на загрузке, clean на стопе) + инициализация
	# маркера сейчас (мы успешно поднялись -> текущее состояние running, не ложный алярм на след. ребуте).
	/etc/init.d/mb-boothealth enable >/dev/null 2>&1 || true
	/usr/share/monkey-business/boothealth.sh boot >/dev/null 2>&1 || true

	# Автостарт: без enable в /etc/rc.d нет S95monkey-business, и после ребута туннель поднимал
	# только cron-watchdog — до минуты трафика LAN мимо VPN на каждой загрузке.
	/etc/init.d/monkey-business enable >/dev/null 2>&1 || true

	# Миграция активного сервера: uci.selected.server -> /etc/monkey-business/active. Деплой
	# сохраняет старый /etc/config, поэтому без переливки дашборд показал бы «Server: none»
	# БЕССРОЧНО: в фазе healthy watchdog не зовёт config_apply, и файл не появится, пока
	# пользователь сам не нажмёт Apply. Секцию после переливки убираем — её больше никто не читает.
	mkdir -p /etc/monkey-business
	OLD_SEL=$(uci -q get monkey-business.selected.server 2>/dev/null || echo '')
	if [ -n "$OLD_SEL" ] && [ ! -s /etc/monkey-business/active ]; then
		printf '%s\n' "$OLD_SEL" > /etc/monkey-business/active
	fi
	if uci -q get monkey-business.selected >/dev/null 2>&1; then
		uci -q delete monkey-business.selected || true
		uci -q commit monkey-business || true
	fi

	# Стоковый init пакета xray-core поднимает ЧУЖОЙ xray со своим конфигом: он жжёт CPU и
	# занимает 10808, на котором висят пробы и socks-фолбэк fetch.sh. Нам нужен только бинарник.
	if [ -x /etc/init.d/xray ]; then
		/etc/init.d/xray stop >/dev/null 2>&1 || true
		/etc/init.d/xray disable >/dev/null 2>&1 || true
	fi

	# cron: watchdog раз в минуту (сам гейтит частоту 60с/10мин по tmpfs) + nicwatch. Идемпотентно,
	# crond включаем.
	#
	# Строку `boothealth.sh beat` (sync + перезапись маркера раз в 5 минут) вычищаем АКТИВНО, а не
	# просто перестаём добавлять: на уже прошитых устройствах она осталась в /etc/crontabs/root и
	# продолжала бы жечь карту — 288 принудительных сбросов в сутки в одни и те же LBA.
	mkdir -p /etc/crontabs
	sed -i '\#monkey-business/boothealth\.sh#d' /etc/crontabs/root 2>/dev/null || true
	WD_LINE='* * * * * /usr/share/monkey-business/watchdog.sh >/dev/null 2>&1'
	NW_LINE='* * * * * /usr/share/monkey-business/nicwatch.sh >/dev/null 2>&1'
	SU_LINE='* * * * * /usr/share/monkey-business/subupdate.sh >/dev/null 2>&1'
	grep -q 'monkey-business/watchdog.sh' /etc/crontabs/root 2>/dev/null \
		|| printf '%s\n' "$WD_LINE" >> /etc/crontabs/root
	grep -q 'monkey-business/nicwatch.sh' /etc/crontabs/root 2>/dev/null \
		|| printf '%s\n' "$NW_LINE" >> /etc/crontabs/root
	grep -q 'monkey-business/subupdate.sh' /etc/crontabs/root 2>/dev/null \
		|| printf '%s\n' "$SU_LINE" >> /etc/crontabs/root
	/etc/init.d/cron enable >/dev/null 2>&1 || true
	/etc/init.d/cron restart >/dev/null 2>&1 || true

	# Рантайм-зависимости (идемпотентно). REQUIRED — без них система нерабочая, деплой ПАДАЕТ:
	# молча отдать роутер без xray/tproxy хуже, чем не задеплоить вовсе. curl тоже REQUIRED:
	# probes.sh/watchdog/failover и socks-фолбэк fetch.sh умеют ТОЛЬКО его — без curl пробы
	# всегда падают и watchdog зациклится на reconnect/failover.
	REQUIRED="ucode-mod-uci ucode-mod-fs rpcd-mod-ucode xray-core kmod-nft-tproxy curl"

	if command -v apk >/dev/null 2>&1; then PM=apk
	elif command -v opkg >/dev/null 2>&1; then PM=opkg
	else PM=""; echo ">> warn: ни apk, ни opkg не найдены — проверь рантайм-зависимости вручную"
	fi

	pkg_have() {
		case "$PM" in
			apk)  apk info -e "$1" >/dev/null 2>&1 ;;
			opkg) opkg list-installed 2>/dev/null | grep -q "^$1 " ;;
			*)    return 0 ;;
		esac
	}
	# вывод в файл, а не в /dev/null: причина отказа (нет репо / конфликт / нет места) нужна
	# на месте — иначе деплой печатает голое «установка не удалась» и диагностировать нечем
	pkg_add() {
		case "$PM" in
			apk)  apk add "$1" >/tmp/mb-pkg.log 2>&1 ;;
			opkg) opkg install "$1" >/tmp/mb-pkg.log 2>&1 ;;
			*)    return 1 ;;
		esac
	}

	if [ -n "$PM" ]; then
		# Индекс обновляем ЯВНО: иначе apk тянет его на лету, и недоступность любого репозитория
		# (напр. kmods) роняет установку целиком — включая пакеты, доступные из других репо.
		echo ">> refreshing package index ($PM)"
		pkg_update() {
			case "$PM" in
				apk)  apk update >/dev/null 2>&1 ;;
				opkg) opkg update >/dev/null 2>&1 ;;
				*)    return 1 ;;
			esac
		}
		if ! pkg_update; then
			echo "   ! индекс не обновился — установка может не найти пакеты"
		fi

		# Ставим ПО ОДНОМУ: apk/opkg транзакционны, и один нерезолвимый пакет откатил бы всю
		# установку разом (так xray-core и не встал из-за битого kmods-индекса).
		for p in $REQUIRED; do
			if pkg_have "$p"; then continue; fi
			echo ">> installing $p"
			if ! pkg_add "$p"; then
				echo "   ! $p: установка не удалась"
				head -n 5 /tmp/mb-pkg.log 2>/dev/null | while read -r l; do echo "     $l"; done
			fi
		done

		for p in $REQUIRED; do
			if ! pkg_have "$p"; then FAILED="${FAILED:-} $p"; fi
		done
		if [ -n "${FAILED:-}" ]; then
			echo "!! КРИТИЧНЫЕ ПАКЕТЫ НЕ УСТАНОВЛЕНЫ:$FAILED" >&2
			echo "!! без них monkey-business нерабочий (xray не стартует / нет TPROXY)." >&2
			echo "!! почини сеть/репозитории и повтори деплой; MB_ALLOW_MISSING=1 — продолжить как есть." >&2
			if [ "${MB_ALLOW_MISSING:-0}" != 1 ]; then exit 1; fi
		fi
	fi

	# Прошивка USB-сетевухи: OpenWrt везёт rtl8153b-2 v2, подвешивающую TX-очередь на R2S
	# (openwrt#22130). Скрипт сам решает, наше ли это железо, и идемпотентен.
	sh /usr/share/monkey-business/nicfw.sh apply || echo "   (nicfw failed — сетевуха останется на пакетной прошивке)"

	# geo-базы + RU-сет из коробки: без geoip.dat/geosite.dat правила geoip:ru/geosite:category-ru не
	# матчат -> direct ломается. Идемпотентно (geo.sh sha-skip).
	if [ ! -s /usr/share/xray/geoip.dat ] || [ ! -s /usr/share/xray/geosite.dat ]; then
		echo ">> downloading geo databases…"
		if ! sh /usr/share/monkey-business/geo.sh download; then
			echo "   ! geo download failed — direct-маршрутизация будет неполной; обнови из UI"
		fi
	fi
	echo ">> building RU direct-bypass set…"
	sh /usr/share/monkey-business/ruset.sh build || echo "   (ru-set build failed — direct-bypass falls back to xray)"

	# dev-VM: убить любые stale/detached rpcd (от прошлого respawn) -> ровно один свежий инстанс,
	# иначе старый rpcd держит в памяти прежний код и отвечает на ubus устаревшими данными.
	if [ "${MB_RESPAWN:-0}" = 1 ]; then
		killall rpcd 2>/dev/null || true
		sleep 1
	fi
	# тихий рестарт: "Failed to connect to ubus" из init-скрипта безвреден и сбивает с толку
	/etc/init.d/rpcd restart >/dev/null 2>&1 || true
	sleep 2

	# ubusd виснет при рестарте rpcd (жив, но не принимает соединения; openwrt#9492). Это случается
	# НЕ только в QEMU, но и на железе (race). Если ubus недоступен — пересоздаём ubusd свежим.
	# Срабатывает ТОЛЬКО при реально зависшем ubus (ретрай отсекает гонку рестарта), поэтому здоровую
	# систему не трогает (gate `! ubus list` = ubusd не отвечает вовсе). Форвардинг трафика от ubus
	# не зависит — клиенты сети не страдают.
	ubus list >/dev/null 2>&1 || sleep 2
	if ! ubus list >/dev/null 2>&1; then
		echo ">> ubus не отвечает (wedge openwrt#9492) — пересоздаю ubusd и перезапускаю сервисы..."
		killall rpcd 2>/dev/null || true
		killall ubusd 2>/dev/null || true
		sleep 1
		rm -f /var/run/ubus/ubus.sock 2>/dev/null || true
		start-stop-daemon -S -b -x /sbin/ubusd 2>/dev/null || setsid /sbin/ubusd </dev/null >/dev/null 2>&1 &
		sleep 2
		# На зависшем ubusd ВСЕ клиенты отвалились и авто-reconnect их объекты не вернул. procd (pid 1)
		# сам переподключается к свежему сокету и возвращает system/service; остальных перезапускаем
		# ЯВНО, иначе критичные объекты не вернутся: netifd -> network.interface (без него WAN-аренда
		# не применяется и шлюз остаётся без интернета), rpcd -> session/uci/luci (без него LuCI падает
		# на session=null), dnsmasq/odhcpd -> DNS/DHCP. network restart на том же LAN-IP established
		# ssh не рвёт (TCP переживает флап той же адресации).
		/etc/init.d/rpcd restart >/dev/null 2>&1 || setsid /sbin/rpcd </dev/null >/dev/null 2>&1 &
		/etc/init.d/network restart >/dev/null 2>&1 || true
		/etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
		/etc/init.d/odhcpd restart >/dev/null 2>&1 || true
		/etc/init.d/uhttpd restart >/dev/null 2>&1 || true
		# ждём перерегистрации netifd ПОЛЛИНГОМ (на R2S медленнее): фиксированные 3с давали ложную
		# перезагрузку у ещё восстанавливающейся системы. Выходим сразу, как объект появился, до ~20с.
		i=0
		while [ "$i" -lt 20 ]; do
			ubus list 2>/dev/null | grep -q '^network\.interface$' && break
			sleep 1; i=$((i + 1))
		done
		# Последний рубеж: если ubus так и не отвечает или netifd не перерегистрировался — надёжно из
		# wedge на железе выводит только чистая перезагрузка. Делаем её ОТЛОЖЕННО и detached (setsid),
		# чтобы ssh успел вернуться и деплой не оборвался на полуслове; пользователь переподключается.
		if ! ubus list >/dev/null 2>&1 || ! ubus list 2>/dev/null | grep -q '^network\.interface$'; then
			echo "!! ubus/netifd не восстановились — роутер перезагрузится через 5с. Переподключись после ребута." >&2
			# sync перед reboot: ubusd в wedge часто утаскивает и procd-shutdown, ребут
			# вырождается в жёсткий сброс, и незакоммиченный журнал ext4 ломает следующую загрузку.
			setsid sh -c 'sleep 5; sync; sync; reboot' </dev/null >/dev/null 2>&1 &
		fi
	fi

	if ubus list 2>/dev/null | grep -q "^monkey-business$"; then
		echo ">> OK: ubus-объект monkey-business зарегистрирован"
	else
		echo ">> WARN: ubus-объект не поднялся. Диагностика: logread | grep -i ucode"
	fi

	# Если VPN сейчас ЗАПУЩЕН — перегенерировать конфиг свежим генератором и переприменить: деплой
	# обновляет код, но живой xray крутится со старым /etc/monkey-business/xray.json до config_apply
	# (обычный рестарт переиспользует старый конфиг). НЕ трогаем, если VPN выключен (не включаем сами).
	if ubus list 2>/dev/null | grep -q "^monkey-business$"; then
		if ubus call monkey-business status 2>/dev/null | grep -q '"running": *true'; then
			echo ">> VPN запущен — переприменяю конфиг новым генератором (config_apply)…"
			ubus call monkey-business config_apply 2>&1 | grep -oE '"(server|error)": *"[^"]*"' || true
		fi
	fi
REMOTE
# Ссылка на LuCI выводится из окружения: localhost (dev-VM, проброс QEMU) -> :$HTTP_PORT;
# реальный хост -> http://<host> (LuCI на :80). MB_LUCI_URL переопределяет явно.
LUCI_HOST="${HOST##*@}"
if [ -n "${MB_LUCI_URL:-}" ]; then
	LUCI_URL="$MB_LUCI_URL"
elif [ "$LUCI_HOST" = localhost ] || [ "$LUCI_HOST" = 127.0.0.1 ]; then
	LUCI_URL="http://localhost:$HTTP_PORT"
else
	LUCI_URL="http://$LUCI_HOST"
fi
echo ">> готово. LuCI: $LUCI_URL (root/root) -> Services -> monkey-business VPN"
