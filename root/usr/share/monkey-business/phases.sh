#!/bin/sh
# Обработчики фаз машины состояний watchdog (healthy / reconnecting / down). Сорсится watchdog.sh
# ПОСЛЕ probes.sh и recovery.sh; сам по себе не исполняется. Стратегия и параметры — watchdog.sh,
# .context/specs/2026-06-23-watchdog-reconnect-strategy.md,
# .context/decisions/2026-07-28-down-phase-failover-budget.md,
# .context/decisions/2026-08-06-recovery-ladder.md.
#
# Работает по общим с watchdog.sh переменным: WD_* (состояние тика), $t (метка начала тика),
# лимиты/таймауты. Побочные эффекты (recover_step, vpn_*, health_check, try_failover, down_backoff,
# log_event, пробы) тоже приходят оттуда — юнит-тест подменяет их своими и гоняет эти обработчики
# как есть.
# SC2154/SC2034 глушатся файлом целиком: WD_* здесь и читаются, и пишутся, но объявлены и
# сохраняются в watchdog.sh, поэтому в границах одного файла выглядят то неинициализированными,
# то никем не используемыми.
# shellcheck shell=sh disable=SC2154,SC2034

# $1 попыток health_check подряд с force-сверкой exit-IP; $2 — необязательный дедлайн (epoch),
# после которого новая попытка не начинается. 0 = здоров.
health_retry() {
	i=0
	while [ "$i" -lt "$1" ]; do
		if [ -n "${2:-}" ] && [ "$(now)" -ge "$2" ]; then return 1; fi
		if health_check 1 "$REC_TIMEOUT"; then return 0; fi
		i=$((i + 1))
		# Пауза только МЕЖДУ попытками: сон после последней сжигал бы секунды тика (а в tick_down —
		# ещё и секунды клампованного бюджета) уже ни на что не влияя.
		[ "$i" -lt "$1" ] && sleep 2
	done
	return 1
}

tick_healthy() {
	vpn_running || vpn_start

	if health_check 0; then
		WD_FAILS=0; WD_NEXT=$((t + POLL)); return
	fi

	WD_FAILS=$((WD_FAILS + 1))
	if [ "$WD_FAILS" -lt "$FAIL_LIMIT" ]; then
		WD_NEXT=$((t + POLL)); return
	fi

	if [ -z "$(direct_probe)" ]; then
		vpn_stop; WD_DOWNKIND=net
		log_event "No connectivity: VPN and direct probes both failing. VPN stopped."
		WD_PHASE=down; WD_FAILS=0; WD_DOWNTRIES=0; down_backoff; return
	fi

	WD_DOWNKIND=vpn
	log_event "VPN exit failing ${FAIL_LIMIT}x (home ${WD_HOME_IP:-?}, last exit ${WD_BASE_IP:-?}). Reconnecting (kill-switch held)."
	WD_PHASE=reconnecting; WD_RECTRIES=0; WD_FAILS=0; WD_NEXT=$t
}

tick_reconnecting() {
	if [ -z "$(direct_probe)" ]; then
		vpn_stop; WD_DOWNKIND=net
		log_event "Network down during reconnect. VPN stopped, LAN on direct."
		WD_PHASE=down; WD_DOWNTRIES=0; down_backoff; return
	fi

	# Одна ступень лестницы на тик, от мягкой к разрушительной (recovery.sh). Мягкий bounce чинит
	# сдохшую сессию при живом процессе, но бессилен против зависшего xray, испорченного firewall
	# и мёртвого сервера — раньше лестница на нём и заканчивалась, и туннель поднимался только
	# руками. Ступень называется в логе: по logread видно, какая именно починила (или не смогла).
	step="$WD_RECTRIES"
	recover_step "$step"
	if health_retry "$REC_TRIES"; then
		log_event "VPN recovered by $(step_name "$step") (exit ${WD_BASE_IP:-?}). Resuming monitoring."
		WD_PHASE=healthy; WD_FAILS=0; WD_RECTRIES=0; WD_NEXT=$((t + POLL)); return
	fi

	WD_RECTRIES=$((WD_RECTRIES + 1))
	if [ "$WD_RECTRIES" -lt "$RECONNECT_LIMIT" ]; then
		log_event "Recovery step '$(step_name "$step")' did not help; escalating to '$(step_name "$WD_RECTRIES")'."
		WD_NEXT=$((t + POLL)); return
	fi

	vpn_stop; WD_DOWNKIND=vpn
	log_event "All ${RECONNECT_LIMIT} recovery steps failed (last: $(step_name "$step")). VPN stopped, LAN on direct."
	WD_PHASE=down; WD_RECTRIES=0; WD_DOWNTRIES=0; down_backoff
}

tick_down() {
	home_now=$(direct_probe)
	if [ -z "$home_now" ]; then
		[ "$WD_DOWNKIND" = vpn ] && { log_event "Network now fully down (direct probe lost)."; WD_DOWNKIND=net; }
		down_backoff; return
	fi
	WD_HOME_IP=$(sane "$home_now")

	[ "$WD_DOWNKIND" = net ] && log_event "Network recovered (direct ok). Attempting VPN."

	deadline=$((t + DOWN_BUDGET))
	# Повторам сохранённого конфига достаётся только голова бюджета — хвост FAILOVER_RESERVE
	# принадлежит перебору серверов и не может быть у него отобран.
	retry_deadline=$((deadline - FAILOVER_RESERVE))
	vpn_start
	if health_retry "$RECOVERY_TRIES" "$retry_deadline"; then
		log_event "VPN restored (exit ${WD_BASE_IP:-?}). Resuming monitoring."
		WD_PHASE=healthy; WD_FAILS=0; WD_RECTRIES=0; WD_DOWNKIND=; WD_DOWNTRIES=0; WD_NEXT=$((t + POLL))
		return
	fi

	# Сохранённый в конфиге сервер мёртв — без failover фаза down была терминальной: раз в
	# BACKOFF поднимали тот же дохлый конфиг и снова гасили (UI вечно «Starting…»).
	# ubus и пост-проверка тоже внутри бюджета: без клампа вход в failover на deadline-1 давал бы
	# ещё UBUS_TIMEOUT + REC_TRIES*(REC_TIMEOUT+2) сверху, т.е. LAN заперта дольше обещанного.
	# Пол FAILOVER_RESERVE: retry-цикл выше упёрся в retry_deadline, так что остаток не меньше
	# резерва, но при съехавших часах кламп не должен опуститься до нерабочих секунд.
	left=$((deadline - $(now)))
	[ "$left" -lt "$FAILOVER_RESERVE" ] && left="$FAILOVER_RESERVE"
	# Хвост резерва — под пост-проверку, и отсчитывается он ОТ ВОЗВРАТА ubus. Общий дедлайн здесь не
	# годится: перебор кандидатов вправе съесть отданный ему потолок целиком, и health_retry вошёл бы
	# с нулём секунд ровно в целевом сценарии (ни один кандидат не прошёл пробу, но конфиг применён
	# и сервис поднят) — то есть судил бы о результате не он, а таймер.
	post=$((REC_TRIES * (REC_TIMEOUT + 2)))
	if try_failover "$((left - post))" && health_retry "$REC_TRIES" "$(( $(now) + post ))"; then
		log_event "Failover restored VPN (exit ${WD_BASE_IP:-?}). Resuming monitoring."
		WD_PHASE=healthy; WD_FAILS=0; WD_RECTRIES=0; WD_DOWNKIND=; WD_DOWNTRIES=0; WD_NEXT=$((t + POLL))
		return
	fi

	vpn_stop
	[ "$WD_DOWNKIND" != vpn ] && log_event "Network up but VPN still failing. Staying on direct."
	WD_DOWNKIND=vpn; down_backoff
}
