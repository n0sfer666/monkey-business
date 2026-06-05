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

# rpcd-плагин + библиотека (src/ -> lib/monkey-business/, чтобы резолвились импорты плагина)
install -D -m644 root/usr/share/rpcd/ucode/monkey-business.uc \
	"$stage/usr/share/rpcd/ucode/monkey-business.uc"
mkdir -p "$stage/usr/share/rpcd/ucode/lib/monkey-business"
cp -R src/. "$stage/usr/share/rpcd/ucode/lib/monkey-business/"

# UCI-конфиг + procd init
install -D -m644 root/etc/config/monkey-business "$stage/etc/config/monkey-business"
install -D -m755 root/etc/init.d/monkey-business "$stage/etc/init.d/monkey-business"

# firewall-скрипты
mkdir -p "$stage/usr/share/monkey-business/firewall"
install -m755 scripts/firewall/apply.sh "$stage/usr/share/monkey-business/firewall/apply.sh"
install -m755 scripts/firewall/flush.sh "$stage/usr/share/monkey-business/firewall/flush.sh"

# LuCI views + menu + acl
mkdir -p "$stage/www/luci-static/resources/view/monkey-business"
cp luci/htdocs/luci-static/resources/view/monkey-business/*.js \
	"$stage/www/luci-static/resources/view/monkey-business/"
install -D -m644 luci/root/usr/share/luci/menu.d/luci-app-monkey-business.json \
	"$stage/usr/share/luci/menu.d/luci-app-monkey-business.json"
install -D -m644 luci/root/usr/share/rpcd/acl.d/luci-app-monkey-business.json \
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
