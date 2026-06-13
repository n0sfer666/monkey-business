#!/bin/sh
# Проверка сплит-маршрутизации через тестовый SOCKS-inbound Xray (см. generator: test_socks).
# Пробит гео-сервис через те же правила, что и TPROXY -> показывает выходной IP/страну.
#   заграничный домен -> proxy -> страна VPN;
#   добавь домен в Direct-лист (dashboard) и повтори -> реальный IP (RU).
#
#   make dev-test-split            # проба ip-api.com
#   make dev-test-split d=ifconfig.co/json-эхо
# Окружение: MB_VM_SSH_PORT(2222) MB_VM_SSH_HOST(root@localhost) MB_VM_SSH_PASS(root)
set -eu

PORT="${MB_VM_SSH_PORT:-2222}"
HOST="${MB_VM_SSH_HOST:-root@localhost}"
PASS="${MB_VM_SSH_PASS:-root}"
DOMAIN="${1:-ip-api.com}"

SSH="ssh"
if command -v sshpass >/dev/null 2>&1 && [ -n "$PASS" ]; then
	# -e: пароль из env SSHPASS, не из argv (иначе виден в `ps`)
	SSHPASS="$PASS"; export SSHPASS
	SSH="sshpass -e ssh"
fi

echo ">> probing exit for '$DOMAIN' via split routing..."
# shellcheck disable=SC2086
$SSH -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
	-o PreferredAuthentications=password -o PubkeyAuthentication=no -p "$PORT" "$HOST" \
	"ubus call monkey-business check_exit '{\"domain\":\"$DOMAIN\"}'"
