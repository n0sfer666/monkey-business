#!/bin/sh
# Прошивка USB-сетевухи RTL8153B (r8152). Команды:
#   nicfw.sh apply    # поставить v1, если железо r8152 и стоит не v1 (идемпотентно)
#   nicfw.sh status   # JSON: driver/installed/pinned
#
# OpenWrt везёт rtl8153b-2 v2 (04/27/23) — она подвешивает TX-очередь на NanoPi R2S
# (openwrt#22130: NETDEV WATCHDOG / Tx timeout / USB-reset, LAN отваливается). FriendlyELEC
# шлёт v1 (10/23/19), на ней бага нет. Держим v1 у себя и ставим поверх пакетной.
# Применяется только после перезагрузки: firmware читается драйвером на probe, а передёргивать
# USB-устройство прямо в деплое нельзя — деплой идёт по этому же LAN.
set -u

SRC="${MB_NICFW_SRC:-/usr/share/monkey-business/firmware/rtl8153b-2.fw}"
DST="${MB_NICFW_DST:-/lib/firmware/rtl_nic/rtl8153b-2.fw}"
KEEP="${MB_NICFW_KEEP:-/etc/sysupgrade.conf}"
SYSNET="${MB_NICFW_SYSNET:-/sys/class/net}"

sha_of() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

# 0 = в системе есть netdev на драйвере r8152 (значит железо наше).
# Имена с _ : в sh переменные глобальные, и без префикса это затирало бы drv у cmd_status.
has_r8152() {
	for _n in "$SYSNET"/*; do
		[ -e "$_n/device/driver" ] || continue
		_drv=$(basename "$(readlink -f "$_n/device/driver" 2>/dev/null)" 2>/dev/null)
		[ "$_drv" = r8152 ] && return 0
	done
	return 1
}

# firmware переживает sysupgrade только если явно в keep-списке
pin_keep() {
	[ -f "$KEEP" ] || return 0
	grep -qxF "$DST" "$KEEP" 2>/dev/null || printf '%s\n' "$DST" >>"$KEEP"
}

cmd_apply() {
	[ -s "$SRC" ] || { echo "nicfw: нет блоба $SRC" >&2; return 1; }
	if ! has_r8152; then
		echo "nicfw: r8152 не найден — пропускаем (не R2S/RTL8153B)"
		return 0
	fi
	if [ -f "$DST" ] && [ "$(sha_of "$DST")" = "$(sha_of "$SRC")" ]; then
		pin_keep
		echo "nicfw: v1 уже стоит"
		return 0
	fi
	mkdir -p "$(dirname "$DST")" || return 1
	cp "$SRC" "$DST.tmp" || return 1
	mv -f "$DST.tmp" "$DST" || { rm -f "$DST.tmp"; return 1; }
	chmod 644 "$DST"
	pin_keep
	echo "nicfw: установлена rtl8153b-2 v1 — вступит в силу после перезагрузки"
}

cmd_status() {
	drv=no; inst=no; pin=no
	has_r8152 && drv=yes
	[ -f "$DST" ] && [ "$(sha_of "$DST")" = "$(sha_of "$SRC")" ] && inst=yes
	grep -qxF "$DST" "$KEEP" 2>/dev/null && pin=yes
	printf '{"driver_r8152":"%s","v1_installed":"%s","kept_on_sysupgrade":"%s"}\n' "$drv" "$inst" "$pin"
}

case "${1:-}" in
	apply)  cmd_apply ;;
	status) cmd_status ;;
	*) echo "usage: $0 {apply|status}" >&2; exit 2 ;;
esac
