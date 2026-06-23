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

# MB_UBUS_RESPAWN раскрывается в удалённую shell-строку -> допускаем только 0/1 (без инъекции)
RESPAWN="${MB_UBUS_RESPAWN:-0}"
case "$RESPAWN" in 0|1) ;; *) RESPAWN=0 ;; esac

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
cpf root/usr/share/monkey-business/geo.sh "$stage/usr/share/monkey-business/geo.sh"
chmod 755 "$stage/usr/share/monkey-business/geo.sh"
cpf root/usr/share/monkey-business/watchdog.sh "$stage/usr/share/monkey-business/watchdog.sh"
chmod 755 "$stage/usr/share/monkey-business/watchdog.sh"
cpf root/usr/share/monkey-business/probes.sh "$stage/usr/share/monkey-business/probes.sh"
chmod 644 "$stage/usr/share/monkey-business/probes.sh"
cpf root/usr/share/monkey-business/boothealth.sh "$stage/usr/share/monkey-business/boothealth.sh"
chmod 755 "$stage/usr/share/monkey-business/boothealth.sh"
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
COPYFILE_DISABLE=1 tar --exclude '.DS_Store' --exclude '._*' -C "$stage" -czf "$tarball" .

echo ">> copying to $HOST:$PORT"
# shellcheck disable=SC2086
$SCP -O $SSH_OPTS -P "$PORT" "$tarball" "$HOST:/tmp/mb-deploy.tgz"

echo ">> installing files + runtime deps + reloading rpcd"
# MB_RESPAWN передаётся в удалённый шелл (значение раскрывается ЛОКАЛЬНО), сам скрипт — через
# stdin-heredoc <<'REMOTE' (без локального раскрытия $ внутри).
# shellcheck disable=SC2086
$SSH $SSH_OPTS -p "$PORT" "$HOST" "MB_RESPAWN='$RESPAWN' sh -s" <<'REMOTE'
	set -e
	# сохранить пользовательский UCI-конфиг (url/серверы/выбор) между деплоями — как conffile
	[ -f /etc/config/monkey-business ] && cp /etc/config/monkey-business /tmp/mb-cfg.keep
	tar -C / -xzf /tmp/mb-deploy.tgz
	[ -f /tmp/mb-cfg.keep ] && mv /tmp/mb-cfg.keep /etc/config/monkey-business
	# подчистить возможные macOS AppleDouble-остатки (BusyBox find без -delete, поэтому rm по glob)
	rm -f /usr/share/rpcd/ucode/._* /usr/share/rpcd/ucode/lib/monkey-business/._* 2>/dev/null || true
	# macOS tar сохраняет локальный uid -> вернуть владельца root:root на развёрнутых путях
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
		/usr/share/monkey-business/watchdog.sh /usr/share/monkey-business/boothealth.sh
	rm -f /tmp/mb-deploy.tgz /tmp/luci-indexcache* 2>/dev/null || true

	# boot-resilience: ранний init-хук (детект unclean/ro на загрузке, clean на стопе) + инициализация
	# маркера сейчас (мы успешно поднялись -> текущее состояние running, не ложный алярм на след. ребуте).
	/etc/init.d/mb-boothealth enable >/dev/null 2>&1 || true
	/usr/share/monkey-business/boothealth.sh boot >/dev/null 2>&1 || true

	# cron: watchdog раз в минуту (сам гейтит частоту 60с/10мин по tmpfs); boothealth beat раз в 5 мин
	# (sync + heartbeat -> меньше теряется при пропаже питания). Идемпотентно, crond включаем.
	mkdir -p /etc/crontabs
	WD_LINE='* * * * * /usr/share/monkey-business/watchdog.sh >/dev/null 2>&1'
	BH_LINE='*/5 * * * * /usr/share/monkey-business/boothealth.sh beat >/dev/null 2>&1'
	grep -q 'monkey-business/watchdog.sh' /etc/crontabs/root 2>/dev/null \
		|| printf '%s\n' "$WD_LINE" >> /etc/crontabs/root
	grep -q 'monkey-business/boothealth.sh' /etc/crontabs/root 2>/dev/null \
		|| printf '%s\n' "$BH_LINE" >> /etc/crontabs/root
	/etc/init.d/cron enable >/dev/null 2>&1 || true
	/etc/init.d/cron restart >/dev/null 2>&1 || true

	# рантайм-зависимости (идемпотентно; для UI хватает uci/fs+rpcd-mod-ucode из LuCI,
	# xray/tproxy нужны только для запуска сервиса). ImmortalWrt/OpenWrt бывает и на apk (24.10+),
	# и на opkg — поддерживаем оба. Не валим деплой при отсутствии сети/пакета.
	PKGS="ucode-mod-uci ucode-mod-fs rpcd-mod-ucode xray-core kmod-nft-tproxy curl"
	if command -v apk >/dev/null 2>&1; then
		for p in $PKGS; do apk info -e "$p" >/dev/null 2>&1 || MISS="${MISS:-} $p"; done
		[ -n "${MISS:-}" ] && { echo ">> installing missing (apk):$MISS"; apk add $MISS >/dev/null 2>&1 || echo "   (apk add не прошёл — нет сети/пакета?)"; }
	elif command -v opkg >/dev/null 2>&1; then
		opkg list-installed >/tmp/mb-pkgs 2>/dev/null || true
		for p in $PKGS; do grep -q "^$p " /tmp/mb-pkgs 2>/dev/null || MISS="${MISS:-} $p"; done
		rm -f /tmp/mb-pkgs
		[ -n "${MISS:-}" ] && { echo ">> installing missing (opkg):$MISS"; { opkg update >/dev/null 2>&1 && opkg install $MISS >/dev/null 2>&1; } || echo "   (opkg install не прошёл — нет сети/пакета?)"; }
	else
		echo ">> warn: ни apk, ни opkg не найдены — проверь рантайм-зависимости вручную"
	fi

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
	# НЕ только в QEMU, но и на железе (race). Если ubus недоступен — пересоздаём ubusd+rpcd свежими.
	# Срабатывает ТОЛЬКО при реально зависшем ubus (ретрай отсекает гонку рестарта), поэтому здоровую
	# систему не трогает. Сам форвардинг трафика от ubus не зависит — клиенты сети не страдают.
	ubus list >/dev/null 2>&1 || sleep 2
	if ! ubus list >/dev/null 2>&1; then
		echo ">> ubus не отвечает (wedge openwrt#9492) — пересоздаю ubusd+rpcd..."
		killall rpcd 2>/dev/null || true
		killall ubusd 2>/dev/null || true
		sleep 1
		rm -f /var/run/ubus/ubus.sock 2>/dev/null || true
		start-stop-daemon -S -b -x /sbin/ubusd 2>/dev/null || setsid /sbin/ubusd </dev/null >/dev/null 2>&1 &
		sleep 2
		start-stop-daemon -S -b -x /sbin/rpcd 2>/dev/null || setsid /sbin/rpcd </dev/null >/dev/null 2>&1 &
		sleep 3
		/etc/init.d/uhttpd restart >/dev/null 2>&1 || true
		sleep 1
	fi

	if ubus list 2>/dev/null | grep -q "^monkey-business$"; then
		echo ">> OK: ubus-объект monkey-business зарегистрирован"
	else
		echo ">> WARN: ubus-объект не поднялся. Диагностика: logread | grep -i ucode"
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
