#!/bin/sh
# Раскладка проекта по реальным путям в dev-VM (или на устройстве) + перезапуск rpcd.
# Требует: VM запущена (make dev-up) и задан пароль root (passwd на консоли VM).
#
# Окружение:
#   MB_VM_SSH_PORT (2222)  MB_VM_SSH_HOST (root@localhost)
set -eu

PORT="${MB_VM_SSH_PORT:-2222}"
HOST="${MB_VM_SSH_HOST:-root@localhost}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

command -v ssh >/dev/null 2>&1 || { echo "ssh required" >&2; exit 1; }

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

# firewall-скрипты
mkdir -p "$stage/usr/share/monkey-business/firewall"
cp scripts/firewall/apply.sh scripts/firewall/flush.sh "$stage/usr/share/monkey-business/firewall/"
chmod 755 "$stage/usr/share/monkey-business/firewall/"*.sh

# LuCI views + menu + acl
mkdir -p "$stage/www/luci-static/resources/view/monkey-business"
cp luci/htdocs/luci-static/resources/view/monkey-business/*.js \
	"$stage/www/luci-static/resources/view/monkey-business/"
cpf luci/root/usr/share/luci/menu.d/luci-app-monkey-business.json \
	"$stage/usr/share/luci/menu.d/luci-app-monkey-business.json"
cpf luci/root/usr/share/rpcd/acl.d/luci-app-monkey-business.json \
	"$stage/usr/share/rpcd/acl.d/luci-app-monkey-business.json"

tar -C "$stage" -czf "$tarball" .

echo ">> copying to $HOST:$PORT (может спросить пароль root)"
# shellcheck disable=SC2086
scp -O $SSH_OPTS -P "$PORT" "$tarball" "$HOST:/tmp/mb-deploy.tgz"

echo ">> installing + restarting rpcd"
# shellcheck disable=SC2086
ssh $SSH_OPTS -p "$PORT" "$HOST" '
	set -e
	tar -C / -xzf /tmp/mb-deploy.tgz
	chmod +x /etc/init.d/monkey-business /usr/share/monkey-business/firewall/*.sh
	rm -f /tmp/mb-deploy.tgz /tmp/luci-indexcache* 2>/dev/null || true
	/etc/init.d/rpcd restart
	echo "deployed: ubus call monkey-business status"
'
