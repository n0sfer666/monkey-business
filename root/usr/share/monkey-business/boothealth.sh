#!/bin/sh
# Boot-resilience хелпер для monkey-business на single-ext4 rootfs (NanoPi R2S, MBR s2=ext4).
#
# ЧЕСТНО О ГРАНИЦАХ: fsck корня ДО монтирования — уровень прошивки/initramfs, из пакета-приложения
# (после загрузки) недостижим. Этот модуль делает то, что реально в наших силах:
#   profilaktika  — периодический sync (beat) сокращает окно «грязных» данных при пропаже питания;
#   диагностика   — трекер clean/unclean + время последней живости -> лог «что и во сколько»;
#   восстановление— если ядро смонтировало root в ro после ext4-ошибок, лог + remount,rw,
#                   чтобы железо осталось управляемым (SSH/LuCI), а не «кирпич».
#
# ПОДКОМАНДЫ: boot (рано в init.d) | beat (cron каждые 5 мин: sync+heartbeat) | clean (init.d stop).
# Маркер /usr/local/.mb-bootstate: content=clean|running, mtime=время последней живости.
# Хук BH_SOURCED=1 — не запускать dispatch (юнит-тест переопределяет функции).
set -u

MARKER=/usr/local/.mb-bootstate
LOG=/usr/local/server.main.log
LOG_MAX="${BH_LOG_MAX:-65536}"

now() { echo "${BH_NOW:-$(date +%s)}"; }
do_sync() { sync; }
root_ro() {
	opts=$(grep -E '^[^ ]+ / [^ ]+ ' /proc/mounts 2>/dev/null | head -1 | cut -d' ' -f4)
	case ",$opts," in *,ro,*) return 0 ;; *) return 1 ;; esac
}
remount_rw() { mount -o remount,rw / 2>/dev/null; }
read_state() { cat "$MARKER" 2>/dev/null || echo ''; }
write_state() { mkdir -p "$(dirname "$MARKER")" 2>/dev/null || true; printf '%s\n' "$1" > "$MARKER"; }
marker_mtime() { stat -c %Y "$MARKER" 2>/dev/null || echo ''; }

log_event() {
	mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
	sz=$(wc -c < "$LOG" 2>/dev/null || echo 0)
	if [ "${sz:-0}" -gt "$LOG_MAX" ]; then
		tail -c $((LOG_MAX / 2)) "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
	fi
	echo "$(date '+%F %T') [mb-boothealth] $1" >> "$LOG"
}

boot() {
	if root_ro; then
		remount_rw
		if root_ro; then rw=no; else rw=yes; fi
		log_event "root fs was read-only at boot (ext4 errors detected). remounted rw=$rw."
	fi
	st=$(read_state)
	mt=$(marker_mtime)
	[ "$st" = running ] && \
		log_event "unclean shutdown detected (last alive ~${mt:-?}, now $(now)). fs integrity at risk."
	write_state running
}

beat() { do_sync; write_state running; }

clean() { write_state clean; do_sync; }

main() {
	cmd="${1:-boot}"
	case "$cmd" in
		boot|beat|clean) "$cmd" ;;
		*) echo "usage: $0 {boot|beat|clean}" >&2; exit 2 ;;
	esac
}

[ "${BH_SOURCED:-0}" = 1 ] || main "$@"
