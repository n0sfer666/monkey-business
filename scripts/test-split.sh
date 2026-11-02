#!/bin/sh
# Проверка сплит-маршрутизации через тестовый SOCKS-inbound Xray (см. generator: test_socks).
# Пробит гео-сервис через те же правила, что и TPROXY -> показывает выходной IP/страну.
#   заграничный домен -> proxy -> страна VPN;
#   добавь домен в Direct-лист (dashboard) и повтори -> реальный IP (RU).
#
#   make dev-test-split            # проба api.ip.sb
#   make dev-test-split d=api.ip.sb
# Окружение: MB_VM_SSH_PORT(2222) MB_VM_SSH_HOST(root@localhost) MB_VM_SSH_PASS(root)
set -eu

PORT="${MB_VM_SSH_PORT:-2222}"
HOST="${MB_VM_SSH_HOST:-root@localhost}"
PASS="${MB_VM_SSH_PASS:-root}"
DOMAIN="${1:-api.ip.sb}"
case "$DOMAIN" in ''|*[!a-zA-Z0-9.-]*) echo 'expected exit-check hostname' >&2; exit 2 ;; esac
case "$HOST" in
 root@localhost|root@127.0.0.1) SSH_OPTS='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null' ;;
 *) SSH_OPTS='-o StrictHostKeyChecking=yes' ;;
esac

SSH="ssh"
if command -v sshpass >/dev/null 2>&1 && [ -n "$PASS" ]; then
	# -e: пароль из env SSHPASS, не из argv (иначе виден в `ps`)
	SSHPASS="$PASS"; export SSHPASS
	SSH="sshpass -e ssh"
fi

echo ">> probing exit for '$DOMAIN' via split routing..."
# shellcheck disable=SC2086
$SSH $SSH_OPTS \
	-o PreferredAuthentications=password -o PubkeyAuthentication=no -p "$PORT" "$HOST" \
	"ubus call monkey-business check_exit '{\"domain\":\"$DOMAIN\"}'"
