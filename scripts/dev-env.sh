#!/bin/sh
set -eu

SSH_PORT="${MB_VM_SSH_PORT:-2222}"
HTTP_PORT="${MB_VM_HTTP_PORT:-8090}"
SUB_FILE="${MB_VM_SUB_FILE:-.context/notes/vpnon-sub.local}"
MARK="/etc/mb-dev-deployed"
UCODE_ADD='let url = trim(require("fs").stdin.read("line") || ""); let c = require("ubus").connect(null, 90); let r = c ? c.call("monkey-business", "subscription_add", { name: "VPNON", url: url }) : null; print(r == null ? "null" : sprintf("%J", r));'

die() { echo "error: $*" >&2; exit 1; }

command -v sshpass >/dev/null 2>&1 || die "не найдено 'sshpass'. Установи: brew install hudochenkov/sshpass/sshpass"
SSHPASS=root
export SSHPASS

vm() {
	sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
		-o ConnectTimeout=5 -o PreferredAuthentications=password -o PubkeyAuthentication=no \
		-p "$SSH_PORT" root@localhost "$@"
}

retry() {
	i=0
	until vm "$1" >/dev/null 2>&1; do
		i=$((i + 1))
		[ "$i" -lt 15 ] || return 1
		sleep 1
	done
}

tree_hash() {
	find luci root src scripts -type f -exec shasum {} + | LC_ALL=C sort | shasum | cut -d' ' -f1
}

provision() {
	if vm 'command -v uhttpd' >/dev/null 2>&1; then
		echo ">> provision: VM уже настроена"
		return 0
	fi
	sh scripts/dev-vm.sh provision
	retry 'command -v uhttpd' || die "после provision нет ssh root/root или uhttpd, см. .dev-vm/console.log"
}

deploy() {
	hash=$(tree_hash)
	if [ "$(vm "cat $MARK" 2>/dev/null)" = "$hash" ]; then
		echo ">> deploy: код не менялся с прошлого деплоя"
		return 0
	fi
	MB_VM_SSH_PASS=root MB_UBUS_RESPAWN=1 MB_HTTP_PORT="$HTTP_PORT" sh scripts/deploy-vm.sh
	retry 'ubus list monkey-business' || die "после deploy нет ubus-объекта monkey-business, см. вывод выше; повтори make dev"
	vm "echo $hash >$MARK"
}

subscription() {
	if [ ! -s "$SUB_FILE" ]; then
		echo ">> подписка: $SUB_FILE нет, пропускаю"
		return 0
	fi
	if vm "uci -q show monkey-business | grep -q \"^monkey-business\\.[^.]*\\.url='[^']\""; then
		echo ">> подписка: уже есть"
		return 0
	fi
	out=$(head -n 1 "$SUB_FILE" | vm "ucode -e '$UCODE_ADD'") || out=null
	case "$out" in
		null) echo "!! подписка: ubus subscription_add не ответил, добавь в LuCI вручную" >&2 ;;
		*'"error"'*) echo "!! подписка: сервер вернул ошибку, добавь в LuCI вручную" >&2 ;;
		*) echo ">> подписка: добавлена из $SUB_FILE" ;;
	esac
}

sh scripts/dev-vm.sh up
provision
deploy
subscription
echo ">> стенд готов: http://localhost:$HTTP_PORT (root/root)"
