#!/bin/sh
set -eu

SSH_PORT="${MB_VM_SSH_PORT:-2222}"
HTTP_PORT="${MB_VM_HTTP_PORT:-8090}"
SUB_FILE="${MB_VM_SUB_FILE:-.context/notes/vpnon-sub.local}"
GEO_CACHE="${MB_GEO_CACHE:-.dev-vm/cache/geo}"
FIXTURE="${MB_FIXTURE:-0}"
FIXTURE_PORT="${MB_FIXTURE_PORT:-18099}"
FIXTURE_HOST="http://10.0.2.2"
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

geo() {
	MB_GEO_CACHE="$GEO_CACHE" sh scripts/dev-geo.sh || echo "!! geo: см. выше; чего нет в кэше, deploy попробует скачать в VM" >&2
	for which in geoip geosite; do
		file="$GEO_CACHE/$which.dat"
		[ -s "$file.sha256" ] || continue
		want=$(cat "$file.sha256")
		if [ "$(vm "sha256sum /usr/share/xray/$which.dat 2>/dev/null" | cut -d' ' -f1)" = "$want" ]; then
			continue
		fi
		vm "mkdir -p /usr/share/xray && cat >/usr/share/xray/$which.dat.part" <"$file" ||
			die "geo: $which не залился в VM"
		vm "cd /usr/share/xray && if [ \"\$(sha256sum $which.dat.part | cut -d' ' -f1)\" = $want ]; then mv -f $which.dat.part $which.dat; else rm -f $which.dat.part; exit 1; fi" ||
			die "geo: $which не лёг в VM целиком"
		echo ">> geo: $which залит в VM из кэша"
	done
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
	if vm "uci -q show monkey-business" | grep "^monkey-business\.[^.]*\.url='[^']" | grep -qv "url='$FIXTURE_HOST:"; then
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

fixture() {
	[ "$FIXTURE" = 1 ] || return 0
	command -v python3 >/dev/null 2>&1 || die "фикстуре нужен python3"
	python3 scripts/fixture/serve.py "$FIXTURE_PORT" scripts/fixture/sub.txt &
	server=$!
	trap 'kill "$server" 2>/dev/null || true' EXIT
	i=0
	until curl -fsS -m 1 -o /dev/null "http://127.0.0.1:$FIXTURE_PORT/sub" 2>/dev/null; do
		kill -0 "$server" 2>/dev/null || die "HTTP фикстуры не поднялся: порт $FIXTURE_PORT занят? (MB_FIXTURE_PORT)"
		i=$((i + 1))
		[ "$i" -lt 20 ] || die "HTTP фикстуры не ответил на :$FIXTURE_PORT"
		sleep 0.5
	done
	kill -0 "$server" 2>/dev/null || die "порт $FIXTURE_PORT занят чужим процессом"
	vm "cat >/tmp/mb-fixture.uc" <scripts/fixture/seed.uc
	vm "MB_FIXTURE_URL=$FIXTURE_HOST:$FIXTURE_PORT/sub ucode /tmp/mb-fixture.uc; rc=\$?; rm -f /tmp/mb-fixture.uc; exit \$rc" ||
		die "фикстура не засеялась, см. вывод выше"
	kill "$server" 2>/dev/null || true
	trap - EXIT
}

sh scripts/dev-vm.sh up
provision
geo
deploy
subscription
fixture
echo ">> стенд готов: http://localhost:$HTTP_PORT (root/root)"
