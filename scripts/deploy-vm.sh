#!/bin/sh
# Раскладка проекта по реальным путям в dev-VM (или на устройстве) + рантайм-зависимости
# + перезапуск rpcd + проверка, что ubus-объект поднялся.
#
# Окружение:
#   MB_VM_SSH_PORT (2222)  MB_VM_SSH_HOST (root@localhost)
#   MB_VM_SSH_PASS — пароль для неинтерактивного входа (нужен sshpass). Пусто => спросит пароль.
#   MB_HTTP_PORT (8080) — только для подсказки с URL LuCI.
set -eu

PORT="${MB_VM_SSH_PORT:-2222}"
HOST="${MB_VM_SSH_HOST:-root@localhost}"
PASS="${MB_VM_SSH_PASS:-}"
HTTP_PORT="${MB_HTTP_PORT:-8080}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

command -v ssh >/dev/null 2>&1 || { echo "ssh required" >&2; exit 1; }

SSH="ssh"
SCP="scp"
if [ -n "$PASS" ]; then
	if command -v sshpass >/dev/null 2>&1; then
		SSH="sshpass -p $PASS ssh"
		SCP="sshpass -p $PASS scp"
	else
		echo "warn: MB_VM_SSH_PASS задан, но sshpass не найден — будет интерактивный ввод" >&2
	fi
fi

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
$SSH $SSH_OPTS -p "$PORT" "$HOST" "MB_RESPAWN='${MB_UBUS_RESPAWN:-0}' sh -s" <<'REMOTE'
	set -e
	# сохранить пользовательский UCI-конфиг (url/серверы/выбор) между деплоями — как conffile
	[ -f /etc/config/monkey-business ] && cp /etc/config/monkey-business /tmp/mb-cfg.keep
	tar -C / -xzf /tmp/mb-deploy.tgz
	[ -f /tmp/mb-cfg.keep ] && mv /tmp/mb-cfg.keep /etc/config/monkey-business
	# подчистить возможные macOS AppleDouble-остатки (BusyBox find без -delete, поэтому rm по glob)
	rm -f /usr/share/rpcd/ucode/._* /usr/share/rpcd/ucode/lib/monkey-business/._* 2>/dev/null || true
	chmod 644 /usr/share/rpcd/ucode/monkey-business.uc
	chmod +x /etc/init.d/monkey-business /usr/share/monkey-business/firewall/*.sh
	rm -f /tmp/mb-deploy.tgz /tmp/luci-indexcache* 2>/dev/null || true

	# рантайм-зависимости (идемпотентно; для UI хватает uci/fs+rpcd-mod-ucode из LuCI,
	# xray/tproxy нужны только для запуска сервиса). Не валим деплой при отсутствии сети.
	if command -v apk >/dev/null 2>&1; then
		for p in ucode-mod-uci ucode-mod-fs rpcd-mod-ucode xray-core kmod-nft-tproxy curl; do
			apk info -e "$p" >/dev/null 2>&1 || MISS="${MISS:-} $p"
		done
		if [ -n "${MISS:-}" ]; then
			echo ">> installing missing:$MISS"
			apk add $MISS >/dev/null 2>&1 || echo "   (apk add не прошёл — нет сети? UI всё равно покажется)"
		fi
	fi

	# тихий рестарт: "Failed to connect to ubus" из init-скрипта безвреден и сбивает с толку
	/etc/init.d/rpcd restart >/dev/null 2>&1 || true
	sleep 2

	# В QEMU-эмуляции boot-time ubusd часто виснет при рестарте rpcd (openwrt#9492): жив, но не
	# принимает соединения. Только для dev-VM (MB_RESPAWN=1) пересоздаём ubusd+rpcd свежими —
	# на реальном железе этого не делаем (флаг не выставлен).
	if ! ubus list >/dev/null 2>&1 && [ "${MB_RESPAWN:-0}" = 1 ]; then
		echo ">> ubus завис (эмуляция QEMU) — пересоздаю ubusd+rpcd..."
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
echo ">> готово. LuCI: http://localhost:$HTTP_PORT (root/root) -> Services -> monkey-business VPN"
