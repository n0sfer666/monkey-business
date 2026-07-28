#!/bin/sh
# Обработчики фаз машины состояний watchdog (healthy / reconnecting / down). Сорсится watchdog.sh
# ПОСЛЕ probes.sh; сам по себе не исполняется. Стратегия и параметры — watchdog.sh,
# .context/specs/2026-06-23-watchdog-reconnect-strategy.md,
# .context/decisions/2026-07-28-down-phase-failover-budget.md.
#
# Работает по общим с watchdog.sh переменным: WD_* (состояние тика), $t (метка начала тика),
# лимиты/таймауты. Побочные эффекты (vpn_*, health_check, try_failover, down_backoff, log_event,
# пробы) тоже приходят оттуда — юнит-тест подменяет их своими и гоняет эти обработчики как есть.
# SC2154/SC2034 глушатся файлом целиком: WD_* здесь и читаются, и пишутся, но объявлены и
# сохраняются в watchdog.sh, поэтому в границах одного файла выглядят то неинициализированными,
# то никем не используемыми.
# shellcheck shell=sh disable=SC2154,SC2034

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

	vpn_reconnect
	i=0
	while [ "$i" -lt "$REC_TRIES" ]; do
		if health_check 1 "$REC_TIMEOUT"; then
			log_event "VPN reconnected (exit ${WD_BASE_IP:-?}). Resuming monitoring."
			WD_PHASE=healthy; WD_FAILS=0; WD_RECTRIES=0; WD_NEXT=$((t + POLL)); return
		fi
		i=$((i + 1)); sleep 2
	done

	WD_RECTRIES=$((WD_RECTRIES + 1))
	if [ "$WD_RECTRIES" -lt "$RECONNECT_LIMIT" ]; then
		WD_NEXT=$((t + POLL)); return
	fi

	# Текущий сервер устойчиво не поднимается -> failover на следующий рабочий по приоритету.
	# config_apply сам пробует кандидатов и перезапускает сервис; подтверждаем health-проверкой.
	if try_failover; then
		i=0
		while [ "$i" -lt "$REC_TRIES" ]; do
			if health_check 1 "$REC_TIMEOUT"; then
				log_event "Failover switched server (exit ${WD_BASE_IP:-?}). Resuming monitoring."
				WD_PHASE=healthy; WD_FAILS=0; WD_RECTRIES=0; WD_NEXT=$((t + POLL)); return
			fi
			i=$((i + 1)); sleep 2
		done
	fi

	vpn_stop; WD_DOWNKIND=vpn
	log_event "Reconnect failed ${RECONNECT_LIMIT}x (no working failover server). VPN stopped, LAN on direct."
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
	i=0; ok=0
	while [ "$i" -lt "$RECOVERY_TRIES" ] && [ "$(now)" -lt "$retry_deadline" ]; do
		if health_check 1 "$REC_TIMEOUT"; then ok=1; break; fi
		i=$((i + 1)); sleep 2
	done

	if [ "$ok" = 1 ]; then
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
	deadline=$(( $(now) + left ))
	if try_failover "$left"; then
		i=0
		while [ "$i" -lt "$REC_TRIES" ] && [ "$(now)" -lt "$deadline" ]; do
			if health_check 1 "$REC_TIMEOUT"; then
				log_event "Failover restored VPN (exit ${WD_BASE_IP:-?}). Resuming monitoring."
				WD_PHASE=healthy; WD_FAILS=0; WD_RECTRIES=0; WD_DOWNKIND=; WD_DOWNTRIES=0; WD_NEXT=$((t + POLL))
				return
			fi
			i=$((i + 1)); sleep 2
		done
	fi

	vpn_stop
	[ "$WD_DOWNKIND" != vpn ] && log_event "Network up but VPN still failing. Staying on direct."
	WD_DOWNKIND=vpn; down_backoff
}
