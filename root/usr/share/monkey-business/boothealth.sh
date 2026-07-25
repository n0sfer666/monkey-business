#!/bin/sh
# Boot-resilience хелпер для monkey-business на single-ext4 rootfs (NanoPi R2S, MBR s2=ext4).
#
# ЧЕСТНО О ГРАНИЦАХ: fsck корня ДО монтирования — уровень прошивки/initramfs, из пакета-приложения
# (после загрузки) недостижим. Этот модуль делает то, что реально в наших силах:
#   диагностика   — трекер clean/unclean + время последней живости -> лог «что и во сколько»;
#   восстановление— если ядро смонтировало root в ro после ext4-ошибок, лог + remount,rw,
#                   чтобы железо осталось управляемым (SSH/LuCI), а не «кирпич».
#
# ПЕРИОДИЧЕСКОГО sync ЗДЕСЬ НЕТ И БЫТЬ НЕ ДОЛЖНО. Бывший `beat` (cron раз в 5 минут: sync +
# перезапись маркера) давал 288 принудительных сбросов в сутки в один и тот же узкий набор LBA
# (голова журнала, блок таблицы инодов /usr/local, суперблок). На SD это read-modify-write целого
# сегмента FTL: карта умирала примерно за две недели, и умирала невидимо — журнал ext4 при штатной
# работе только пишется, читается лишь при монтировании, поэтому износ вскрывался ровно на ребуте
# отказом replay -> «Errors behavior: Remount read-only». Маркер трогаем 2 раза за цикл питания.
#
# ПОДКОМАНДЫ: boot (рано в init.d) | clean (init.d stop).
# Маркер /usr/local/.mb-bootstate: content=clean|running, mtime=время последней живости.
# Хук BH_SOURCED=1 — не запускать dispatch (юнит-тест переопределяет функции).
set -u

MARKER=/usr/local/.mb-bootstate

now() { echo "${BH_NOW:-$(date +%s)}"; }
root_ro() {
	opts=$(grep -E '^[^ ]+ / [^ ]+ ' /proc/mounts 2>/dev/null | head -1 | cut -d' ' -f4)
	case ",$opts," in *,ro,*) return 0 ;; *) return 1 ;; esac
}
remount_rw() { mount -o remount,rw / 2>/dev/null; }
read_state() { cat "$MARKER" 2>/dev/null || echo ''; }
write_state() { mkdir -p "$(dirname "$MARKER")" 2>/dev/null || true; printf '%s\n' "$1" > "$MARKER"; }
marker_mtime() { stat -c %Y "$MARKER" 2>/dev/null || echo ''; }

# syslog вместо своего файла на rootfs: ring buffer в RAM, ноль записей на карту и ноль
# самописной ротации (её .tmp ещё и гонялся с watchdog-ом за одно и то же имя). Тег mb-event
# общий с watchdog и отдельный от monkey-business, под которым init.d сыплет служебные строки
# apply.sh/flush.sh.
log_event() { logger -t mb-event "boothealth: $1"; }

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

# Единственный sync за цикл питания — на штатном стопе, чтобы маркер `clean` реально дошёл
# до карты: иначе следующая загрузка увидит `running` и объявит ложный unclean.
clean() { write_state clean; sync; }

main() {
	cmd="${1:-boot}"
	case "$cmd" in
		boot|clean) "$cmd" ;;
		*) echo "usage: $0 {boot|clean}" >&2; exit 2 ;;
	esac
}

[ "${BH_SOURCED:-0}" = 1 ] || main "$@"
