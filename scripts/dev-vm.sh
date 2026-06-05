#!/bin/sh
# Dev-VM: ImmortalWrt aarch64 (armsr/armv8 generic) в QEMU для разработки.
# Архитектура совпадает с NanoPi R2S (aarch64); финал — на железе.
#
# Запускается ФОНОВО (headless), консоль — на unix-сокете, весь вывод пишется в лог.
# Подкоманды: up | provision | console | ssh | down | clean | status
#
# Окружение: MB_VM_SSH_PORT(2222) MB_VM_HTTP_PORT(8080) MB_VM_MEM(512) MB_IMMORTALWRT_URL
set -u

VMDIR=".dev-vm"
SSH_PORT="${MB_VM_SSH_PORT:-2222}"
HTTP_PORT="${MB_VM_HTTP_PORT:-8080}"
MEM="${MB_VM_MEM:-512}"
DEFAULT_URL="https://downloads.immortalwrt.org/snapshots/targets/armsr/armv8/immortalwrt-armsr-armv8-generic-ext4-combined-efi.img.gz"
IMG_URL="${MB_IMMORTALWRT_URL:-$DEFAULT_URL}"
DISK="$VMDIR/disk.img"
FW="$VMDIR/edk2-aarch64-code.fd"
SOCK="$VMDIR/console.sock"
LOG="$VMDIR/console.log"
PID="$VMDIR/qemu.pid"

die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "не найдено '$1'. Установи: $2"; }

is_running() {
	[ -f "$PID" ] && kill -0 "$(cat "$PID" 2>/dev/null)" 2>/dev/null
}

ensure_assets() {
	mkdir -p "$VMDIR"
	if [ ! -f "$DISK" ]; then
		echo ">> скачиваю образ ImmortalWrt aarch64..."
		need curl "brew install curl"
		curl -fL "$IMG_URL" -o "$VMDIR/disk.img.gz" || die "не удалось скачать образ"
		gunzip -f "$VMDIR/disk.img.gz" || die "не удалось распаковать образ"
		qemu-img resize "$DISK" 512M >/dev/null 2>&1 || true
	fi
	if [ ! -f "$FW" ]; then
		for p in /opt/homebrew/share/qemu/edk2-aarch64-code.fd /usr/local/share/qemu/edk2-aarch64-code.fd; do
			[ -f "$p" ] && cp "$p" "$FW" && break
		done
		[ -f "$FW" ] || die "не найдена edk2-aarch64-code.fd (часть пакета qemu)"
	fi
}

cmd_up() {
	need qemu-system-aarch64 "brew install qemu"
	need qemu-img "brew install qemu"
	if is_running; then
		echo ">> VM уже запущена (pid $(cat "$PID")). SSH :$SSH_PORT, LuCI :$HTTP_PORT"
		return 0
	fi
	ensure_assets
	rm -f "$SOCK" "$LOG"
	echo ">> запускаю dev-VM (headless, фоном)..."
	nohup qemu-system-aarch64 \
		-M virt -cpu cortex-a72 -smp 2 -m "$MEM" \
		-bios "$FW" \
		-drive "file=$DISK,if=virtio,format=raw" \
		-device virtio-net-pci,netdev=lan \
		-netdev "user,id=lan,hostfwd=tcp::$SSH_PORT-:22,hostfwd=tcp::$HTTP_PORT-:80" \
		-display none \
		-chardev "socket,id=con,path=$SOCK,server=on,wait=off,logfile=$LOG" \
		-serial chardev:con \
		>"$VMDIR/qemu.log" 2>&1 &
	qpid=$!
	echo "$qpid" >"$PID"
	echo ">> ожидаю загрузку..."
	i=0
	while [ "$i" -lt 120 ]; do
		grep -q "activate this console" "$LOG" 2>/dev/null && break
		kill -0 "$qpid" 2>/dev/null || die "QEMU упал, см. $VMDIR/qemu.log"
		sleep 1; i=$((i + 1))
	done
	echo ">> VM загружена. Дальше: make dev-provision (один раз), затем make dev-ssh / http://localhost:$HTTP_PORT"
}

cmd_provision() {
	is_running || die "VM не запущена (make dev-up)"
	need python3 "входит в macOS"
	python3 scripts/vm-provision.py "$SOCK"
}

cmd_console() {
	is_running || die "VM не запущена (make dev-up)"
	echo ">> консоль VM (выход: Ctrl-C — VM продолжит работать). Enter для приглашения."
	if command -v nc >/dev/null 2>&1; then
		nc -U "$SOCK"
	else
		python3 - "$SOCK" <<'PY'
import socket,sys,threading
s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); s.connect(sys.argv[1])
threading.Thread(target=lambda:[sys.stdout.write(s.recv(4096).decode("utf-8","replace")) or sys.stdout.flush() for _ in iter(int,1)],daemon=True).start()
for line in sys.stdin: s.sendall(line.encode())
PY
	fi
}

cmd_ssh() {
	need ssh "ssh из системы"
	echo ">> пароль: root (задаётся make dev-provision)"
	exec ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		-o PreferredAuthentications=password -o PubkeyAuthentication=no \
		-p "$SSH_PORT" "root@localhost"
}

cmd_down() {
	if is_running; then
		kill "$(cat "$PID")" 2>/dev/null
		echo ">> VM остановлена"
	else
		echo ">> VM не запущена (по pidfile)"
	fi
	pkill -f "qemu-system-aarch64.*$DISK" 2>/dev/null || true
	rm -f "$PID" "$SOCK"
}

cmd_status() {
	if is_running; then
		echo "VM: running (pid $(cat "$PID")) | SSH localhost:$SSH_PORT | LuCI http://localhost:$HTTP_PORT"
	else
		echo "VM: stopped"
	fi
}

cmd_clean() {
	cmd_down
	rm -rf "$VMDIR"
	echo ">> $VMDIR удалён"
}

case "${1:-}" in
	up)        cmd_up ;;
	provision) cmd_provision ;;
	console)   cmd_console ;;
	ssh)       cmd_ssh ;;
	down)      cmd_down ;;
	status)    cmd_status ;;
	clean)     cmd_clean ;;
	*)         echo "usage: $0 {up|provision|console|ssh|down|status|clean}" >&2; exit 2 ;;
esac
