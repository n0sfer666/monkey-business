#!/bin/sh
# shellcheck shell=sh

wd_lock_dir() {
	mkdir "$1.d" 2>/dev/null && return 0
	# mkdir атомарен; протухший лок (>15 мин) снимаем, иначе watchdog умрёт навсегда.
	# Гонка на снятии протухшего лока безопасна: тики раз в минуту, а победитель сразу
	# обновляет mtime каталога — второй претендент уже не увидит его протухшим.
	age=$(stat -c %Y "$1.d" 2>/dev/null || echo 0)
	[ "$(( $(date +%s) - age ))" -gt 900 ] || return 1
	rmdir "$1.d" 2>/dev/null
	mkdir "$1.d" 2>/dev/null
}

wd_lock() {
	WD_LOCK_HELD=$1
	wd_wait=${2:-0}
	mb_private_dir "${1%/*}" && mb_private_file "$1" || return 1
	if command -v flock >/dev/null 2>&1; then
		exec 9>"$1"
		set -- flock -n 9
	else
		set -- wd_lock_dir "$1"
	fi
	until "$@"; do
		[ "$wd_wait" -gt 0 ] || return 1
		wd_wait=$((wd_wait - 1))
		sleep 1
	done
	[ "$1" != flock ] || return 0
	trap 'rmdir "$WD_LOCK_HELD.d" 2>/dev/null' EXIT
	trap 'rmdir "$WD_LOCK_HELD.d" 2>/dev/null; exit 143' INT TERM
}
