#!/bin/sh
# NIC-watchdog для USB-сетевухи r8152 (cron раз в минуту). Стоит на страховке от залипания
# TX-очереди RTL8153B (openwrt#22130) на случай, если nicfw.sh не применён или v1 тоже словит баг.
#
# Сигнал залипания: tx_errors вырос И tx_packets НЕ вырос — очередь встала. Роста одних лишь
# tx_errors недостаточно (счётчик растёт и от безобидных ошибок), иначе watcher ронял бы живой LAN.
#
# Эскалация: 1-й страйк — bounce линка; 2-й и далее — re-bind USB-устройства к драйверу.
# Env-override: MB_NIC_IFACE(eth1) MB_NIC_STATE_DIR(/tmp/mb-nicwatch) MB_NIC_SYSNET MB_NIC_USBDRV.
set -u

IFACE="${MB_NIC_IFACE:-eth1}"
STATE_DIR="${MB_NIC_STATE_DIR:-/tmp/mb-nicwatch}"
SYSNET="${MB_NIC_SYSNET:-/sys/class/net}"
USBDRV="${MB_NIC_USBDRV:-/sys/bus/usb/drivers/r8152}"
STATE="$STATE_DIR/state"
DEVFILE="$STATE_DIR/usbdev.$IFACE"

MAX_REBIND=4
BACKOFF=10

STAT="$SYSNET/$IFACE/statistics"

log() { logger -t mb-nicwatch "$@" 2>/dev/null || true; }
# пустой/битый sysfs-счётчик -> 0: иначе [ -lt ] упадёт и вотчер молча перестанет реагировать
num() { case "${1:-}" in '' | *[!0-9]*) echo 0 ;; *) echo "$1" ;; esac; }
rd() { num "$(cat "$STAT/$1" 2>/dev/null)"; }

# unbind уже снёс netdev: если bind не пройдёт, eth1 (вся LAN) исчезнет до ручной перезагрузки
bind_dev() {
	_bd="$1"; _i=0
	while [ "$_i" -lt 3 ]; do
		printf '%s' "$_bd" >"$USBDRV/bind" 2>/dev/null
		sleep 2
		[ -d "$SYSNET/$IFACE" ] && return 0
		_i=$((_i + 1))
	done
	return 1
}

# Интерфейса нет — возможно, мы сами его отвязали, а bind не прошёл. Без этой попытки скрипт
# вечно выходил бы по "нет интерфейса", а LAN осталась бы мёртвой.
if [ ! -d "$STAT" ]; then
	_lost="$(cat "$DEVFILE" 2>/dev/null || echo "")"
	[ -n "$_lost" ] && [ -d "$USBDRV" ] || exit 0
	if bind_dev "$_lost"; then
		rm -f "$DEVFILE"
		log "$IFACE вернулся после повторного USB bind"
	else
		log "$IFACE отсутствует, повторный USB bind не помог"
	fi
	exit 0
fi

bounce_link() {
	ip link set "$IFACE" down 2>/dev/null || return 1
	sleep 1
	ip link set "$IFACE" up 2>/dev/null || return 1
}

# Firmware читается на probe, поэтому только re-bind реально пересбрасывает залипший контроллер.
rebind_usb() {
	_dev=$(basename "$(readlink -f "$SYSNET/$IFACE/device" 2>/dev/null)" 2>/dev/null)
	[ -n "$_dev" ] && [ -d "$USBDRV" ] || return 1
	# без маркера отвязку потом не восстановить -> лучше не чинить, чем потерять LAN безвозвратно
	printf '%s' "$_dev" >"$DEVFILE" 2>/dev/null || return 1
	printf '%s' "$_dev" >"$USBDRV/unbind" 2>/dev/null || { rm -f "$DEVFILE"; return 1; }
	sleep 2
	bind_dev "$_dev" || return 1
	rm -f "$DEVFILE"
	return 0
}

err=$(rd tx_errors)
pkt=$(rd tx_packets)

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
read -r p_err p_pkt p_strikes 2>/dev/null <"$STATE" || { p_err=""; p_pkt=""; p_strikes=""; }
p_err="$(num "${p_err:-$err}")"
p_pkt="$(num "${p_pkt:-$pkt}")"
p_strikes="$(num "${p_strikes:-0}")"

# счётчики обнулились (re-probe драйвера) -> базлайн заново, без реакции
if [ "$err" -lt "$p_err" ] || [ "$pkt" -lt "$p_pkt" ]; then
	printf '%s %s 0\n' "$err" "$pkt" >"$STATE"
	exit 0
fi

stuck=0
[ "$err" -gt "$p_err" ] && [ "$pkt" -eq "$p_pkt" ] && stuck=1

if [ "$stuck" = 0 ]; then
	printf '%s %s 0\n' "$err" "$pkt" >"$STATE"
	exit 0
fi

strikes=$((p_strikes + 1))
printf '%s %s %s\n' "$err" "$pkt" "$strikes" >"$STATE"

if [ "$strikes" -ge 2 ]; then
	# ронять LAN каждую минуту бессмысленно (re-bind уже не помог) и мешает чинить руками
	if [ "$strikes" -le "$MAX_REBIND" ] || [ $((strikes % BACKOFF)) -eq 0 ]; then
		if rebind_usb; then
			log "TX-очередь $IFACE встала (tx_errors $p_err->$err, страйк $strikes): USB re-bind выполнен"
		else
			log "TX-очередь $IFACE встала (страйк $strikes): USB re-bind НЕ УДАЛСЯ"
		fi
	else
		log "TX-очередь $IFACE всё ещё стоит (страйк $strikes): re-bind не помогает, пауза"
	fi
elif bounce_link; then
	log "TX-очередь $IFACE встала (tx_errors $p_err->$err): линк передёрнут"
else
	log "TX-очередь $IFACE встала: bounce линка НЕ УДАЛСЯ"
fi
