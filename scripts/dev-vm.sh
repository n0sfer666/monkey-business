#!/bin/sh
# Dev-VM: ImmortalWrt aarch64 (armsr/armv8 generic) в QEMU для разработки UI/логики.
# Архитектура совпадает с NanoPi R2S (aarch64); финальные сетевые/перф-тесты — на железе.
#
# Подкоманды: up | ssh | down | clean
# Окружение:
#   MB_IMMORTALWRT_URL  — URL combined-efi образа (по умолчанию ниже)
#   MB_VM_SSH_PORT      — проброс SSH (по умолчанию 2222)
#   MB_VM_HTTP_PORT     — проброс LuCI/HTTP (по умолчанию 8080)
#   MB_VM_MEM           — память VM (по умолчанию 512)
set -u

VMDIR=".dev-vm"
SSH_PORT="${MB_VM_SSH_PORT:-2222}"
HTTP_PORT="${MB_VM_HTTP_PORT:-8080}"
MEM="${MB_VM_MEM:-512}"
DEFAULT_URL="https://downloads.immortalwrt.org/snapshots/targets/armsr/armv8/immortalwrt-armsr-armv8-generic-ext4-combined-efi.img.gz"
IMG_URL="${MB_IMMORTALWRT_URL:-$DEFAULT_URL}"
DISK="$VMDIR/disk.img"
FW="$VMDIR/edk2-aarch64-code.fd"

die() { echo "error: $*" >&2; exit 1; }

need() {
	command -v "$1" >/dev/null 2>&1 || die "не найдено '$1'. Установи: $2"
}

cmd_up() {
	need qemu-system-aarch64 "brew install qemu"
	need qemu-img "brew install qemu"
	mkdir -p "$VMDIR"

	if [ ! -f "$DISK" ]; then
		echo ">> скачиваю образ ImmortalWrt aarch64..."
		need curl "brew install curl"
		curl -fL "$IMG_URL" -o "$VMDIR/disk.img.gz" || die "не удалось скачать образ"
		gunzip -f "$VMDIR/disk.img.gz" || die "не удалось распаковать образ"
		qemu-img resize "$DISK" 512M >/dev/null 2>&1 || true
	fi

	if [ ! -f "$FW" ]; then
		# UEFI-прошивка для aarch64 virt. Путь зависит от установки qemu (brew).
		for p in \
			/opt/homebrew/share/qemu/edk2-aarch64-code.fd \
			/usr/local/share/qemu/edk2-aarch64-code.fd; do
			[ -f "$p" ] && cp "$p" "$FW" && break
		done
		[ -f "$FW" ] || die "не найдена edk2-aarch64-code.fd (часть пакета qemu)"
	fi

	echo ">> запускаю dev-VM (SSH: localhost:$SSH_PORT, LuCI: http://localhost:$HTTP_PORT)"
	exec qemu-system-aarch64 \
		-M virt -cpu cortex-a72 -smp 2 -m "$MEM" \
		-bios "$FW" \
		-drive "file=$DISK,if=virtio,format=raw" \
		-device virtio-net-pci,netdev=lan \
		-netdev "user,id=lan,hostfwd=tcp::$SSH_PORT-:22,hostfwd=tcp::$HTTP_PORT-:80" \
		-nographic
}

cmd_ssh() {
	need ssh "ssh из системы"
	exec ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		-p "$SSH_PORT" "root@localhost"
}

cmd_down() {
	pkill -f "qemu-system-aarch64.*$DISK" 2>/dev/null && echo ">> VM остановлена" || echo ">> VM не запущена"
}

cmd_clean() {
	cmd_down
	rm -rf "$VMDIR"
	echo ">> $VMDIR удалён"
}

case "${1:-}" in
	up)    cmd_up ;;
	ssh)   cmd_ssh ;;
	down)  cmd_down ;;
	clean) cmd_clean ;;
	*)     echo "usage: $0 {up|ssh|down|clean}" >&2; exit 2 ;;
esac
