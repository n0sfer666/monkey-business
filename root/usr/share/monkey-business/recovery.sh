#!/bin/sh
# Лестница восстановления VPN для watchdog: от самой дешёвой ступени к самой разрушительной.
# Сорсится watchdog.sh ПОСЛЕ probes.sh и ДО phases.sh; сам по себе не исполняется. Параметры и
# состояние — watchdog.sh, порядок вызова ступеней — phases.sh (tick_reconnecting).
#
# Ступени (recover_step N), каждая на своём тике:
#   0 soft   SIGTERM xray, procd респавнит. Кроме процесса не трогаем ничего.
#   1 hard   SIGTERM -> ждём РЕАЛЬНОЙ смерти -> SIGKILL -> init.d start (apply.sh пересобирает
#            nft-таблицу). Kill-switch не снимается ни на секунду.
#   2 fail   config_apply: перебор серверов эфемерной пробой, новый конфиг, рестарт сервиса.
#   3 full   config_apply -> init.d stop (flush.sh снимает таблицу и ip-rule) -> start.
#            Полный аналог ручного Turn off/Turn on — вместе с окном, когда LAN идёт открытым direct.
# SC2154/SC2034 глушатся файлом целиком по той же причине, что и в phases.sh: параметры (WD_*,
# лимиты, XRAY_MATCH) объявлены в watchdog.sh, а WD_PROBED/WD_TAGSIG отсюда только пишутся —
# читают их phases.sh и watchdog.sh.
# SC2119/SC2120 — тоже файлом: потолок ubus у try_failover/failover_step необязателен и задаётся
# только из tick_down, отсюда они зовутся без аргументов, и это норма, а не забытый параметр.
# shellcheck shell=sh disable=SC2154,SC2034,SC2119,SC2120

# Матч по cmdline боевого конфига, а не `pidof xray`: иначе эфемерная проба failover
# (/tmp/mb-probe.json) и чужой xray из стокового пакета считаются «сервис жив».
# Без pgrep (урезанный busybox) деградируем до pidof: грубее, но лучше вечного «сервис мёртв».
if command -v pgrep >/dev/null 2>&1; then
	xray_pids() { pgrep -f "$XRAY_MATCH"; }
else
	xray_pids() { pidof xray; }
fi
pidset() { xray_pids 2>/dev/null | tr '\n' ' '; }
vpn_running() { xray_pids >/dev/null 2>&1; }
vpn_start() { $INIT start >/dev/null 2>&1; sleep 5; }
vpn_stop() { $INIT stop >/dev/null 2>&1; }

vpn_reconnect() {
	# shellcheck disable=SC2046
	kill $(xray_pids) 2>/dev/null || true
	sleep "$RECONNECT_WAIT"
	vpn_running || vpn_start
}

# Жив ли хоть один из ПЕРЕДАННЫХ pid'ов. Сравнивать наборы «до/после» нельзя: без pgrep xray_pids
# деградирует до pidof и ловит в том числе эфемерную пробу failover (/tmp/mb-probe.json) — её
# самостоятельный выход менял бы набор и выдавался за смерть боевого процесса.
any_alive() {
	for p in $1; do kill -0 "$p" 2>/dev/null && return 0; done
	return 1
}

# До SIGTERM зависший xray может не дойти вовсе — а мягкой ступени этого не видно: процесс жив,
# значит «поднялся», и она молча не делает ничего. Здесь смерть подтверждается поимённо, дожимается
# SIGKILL, а подъём идёт через init.d — заодно apply.sh пересобирает nft-таблицу.
vpn_hard_restart() {
	vpn_running || { vpn_start; return; }
	was=$(pidset)
	# Процесс исчез между проверкой и снимком (procd, ручной Off): ждать смерти уже некого,
	# иначе цикл ниже впустую выспал бы весь KILL_WAIT из и без того дефицитного тика.
	[ -n "$was" ] || { vpn_start; return; }
	# shellcheck disable=SC2086
	kill $was 2>/dev/null || true
	i=0
	while [ "$i" -lt "$KILL_WAIT" ] && any_alive "$was"; do
		sleep 1; i=$((i + 1))
	done
	if any_alive "$was"; then
		# shellcheck disable=SC2086
		kill -9 $was 2>/dev/null || true
		sleep 2
	fi
	vpn_start
}

# Ровно то, чем пользователь чинит туннель руками, когда всё остальное бессильно: перевыбрать сервер
# и собрать всё с нуля. Порядок именно такой: config_apply идёт ПЕРВЫМ, под поднятым kill-switch'ем
# (он делает init.d reload, таблицу не снимает), и только потом stop/start. Обратный порядок держал
# бы LAN открытой всё время перебора кандидатов — до UBUS_TIMEOUT, единственное место в коде, где
# утечка была бы без потолка. Так окно = длительность stop+start, т.е. секунды; поэтому ступень и
# стоит последней перед down, где LAN и так остаётся на direct.
vpn_full_cycle() {
	failover_step
	vpn_stop
	vpn_start
}

# Failover: rpcd пересобирает конфиг на первый рабочий сервер по приоритету (config_apply ->
# selectWorking с реальными эфемерными пробами) и перезапускает сервис. Имя-агностично.
# $1 — потолок ожидания ubus в секундах (по умолчанию UBUS_TIMEOUT); tick_down зажимает его
# остатком своего бюджета, чтобы kill-switch не висел дольше обещанного.
#
# Возврат 0 = config_apply отработал, сервис переприменён. probed:true значит лишь, что кандидат
# прошёл эфемерную пробу; probed:false — фолбэк на servers[0], но конфиг ВСЁ РАВНО применён и сервис
# поднят, и ровно так же ведёт себя ручной Turn on. Раньше probed:false читался как «переключиться
# не удалось»: health-проверка пропускалась, и watchdog уходил в down по живому туннелю — а
# пользователь тем же самым тумблером поднимал его руками с первого раза.
failover_switch() {
	res=$(ubus -t "${1:-$UBUS_TIMEOUT}" call "$CONFIG" config_apply 2>/dev/null) || return 1
	WD_PROBED=0
	printf '%s' "$res" | grep -q '"probed": *true' && WD_PROBED=1
	! printf '%s' "$res" | grep -q '"error"[[:space:]]*:'
}
# config_apply в ЛЮБОМ исходе зовёт setSelected, т.е. тег меняем мы сами. Без пересинхронизации
# WD_TAGSIG следующий тик принял бы это за ручной выбор пользователя, сбросил фазу и обнулил
# backoff — вместо отдыха в 10 минут получился бы полный перебор кандидатов раз в минуту.
# $1 (потолок ubus) необязателен: его задаёт только tick_down, зажимая остатком своего бюджета.
try_failover() {
	failover_switch "$@"; fo=$?
	WD_TAGSIG=$(sig "$(selected_tag)")
	return "$fo"
}

# Ступень failover как отдельное событие в mb-event: по общей строке «escalating» не отличить
# «config_apply отработал, но не помогло» от «config_apply не отработал вовсе» (мёртвый rpcd,
# таймаут ubus), а это разные инциденты с разным лечением.
failover_step() {
	if ! try_failover "$@"; then
		log_event "config_apply failed (rpcd down or ubus timeout)."
	elif [ "$WD_PROBED" = 1 ]; then
		log_event "config_apply switched to a server that passed the probe."
	else
		log_event "config_apply re-applied the config; no candidate passed the probe."
	fi
}

step_name() {
	case "${1:-0}" in
		0) echo "soft bounce" ;;
		1) echo "hard restart" ;;
		2) echo "failover" ;;
		*) echo "full stop/start" ;;
	esac
}
recover_step() {
	case "${1:-0}" in
		0) vpn_reconnect ;;
		1) vpn_hard_restart ;;
		2) failover_step ;;
		*) vpn_full_cycle ;;
	esac
}
