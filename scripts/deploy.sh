#!/bin/sh
# Деплой/ОБНОВЛЕНИЕ на реальное устройство (NanoPi R2S и пр.). Тонкая обёртка над deploy-vm.sh.
#
# deploy-vm.sh сам идемпотентен и сохраняет UCI-конфиг между заливками -> повторный запуск = update
# (новые файлы перетираются, конфиг/серверы/выбор остаются, cron/init регистрируются без дублей).
# Эта обёртка лишь: гонит локальные проверки ПЕРЕД заливкой (не отправлять сломанное) и задаёт
# device-дефолты (SSH :22), переиспользуя всю тяжёлую логику развёртывания.
#
#   MB_HOST=root@192.168.1.1 sh scripts/deploy.sh
#   MB_HOST=... MB_PORT=22 MB_PASS=secret sh scripts/deploy.sh
#   MB_HOST=... MB_SKIP_CHECKS=1 sh scripts/deploy.sh    # пропустить проверки (нет Docker под рукой)
set -eu

HOST="${MB_HOST:-}"
[ -n "$HOST" ] || { echo "set MB_HOST=root@<router-ip>  (например root@192.168.1.1)" >&2; exit 2; }

CHECK_CMD="${MB_CHECK_CMD:-make lint check test-unit}"
DEPLOY_CMD="${MB_DEPLOY_CMD:-sh scripts/deploy-vm.sh}"

if [ "${MB_SKIP_CHECKS:-0}" != 1 ]; then
	echo ">> локальные проверки перед заливкой…"
	# shellcheck disable=SC2086
	$CHECK_CMD
fi

echo ">> деплой на ${HOST}…"
# shellcheck disable=SC2086
MB_VM_SSH_HOST="$HOST" MB_VM_SSH_PORT="${MB_PORT:-22}" MB_VM_SSH_PASS="${MB_PASS:-}" $DEPLOY_CMD
