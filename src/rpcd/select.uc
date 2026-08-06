// Выбор активного сервера и failover по приоритету. Отдельный файл: это единственное место, где
// решается, какой сервер получит трафик, и его цена — «интернета нет» при ошибке.

import { isHysteria } from "../generator/hysteria.uc";

// Порядок серверов = порядок секций UCI (drag-reorder в GridSection) — единственный источник
// приоритета. Backend и UI уважают этот порядок; re-fetch его сохраняет (см. subscriptionUpdate).
function orderedServers(ctx) {
	return ctx.getServers();
}

// Активный сервер = ПЕРВЫЙ по приоритету (порядок секций UCI = предпочтение пользователя).
// Probe доступности (nc/tcpPing) здесь ненадёжен (даёт ложные негативы даже на рабочих Reality-
// серверах), поэтому не используем его для выбора. Реальный runtime-failover — через Xray balancer
// (отдельная фича). "Test latency" в UI остаётся как информация.
function selectBest(ctx) {
	let servers = orderedServers(ctx);
	if (length(servers) == 0)
		return null;
	let chosen = servers[0];
	ctx.setSelected(chosen.tag);
	return chosen;
}

// Кандидат, который заведомо не поднимется (hysteria без установленного клиента), выбывает ДО пробы.
// Иначе hysteria на первой позиции ломала фолбэк: prepareHysteria отказывал на servers[0], и
// config_apply не применял НИЧЕГО при живых vless ниже по списку — а recovery.sh на этом отказе
// делает фазу down терминальной (ровно тот дефект, что чинил 8146280). Незапускаемых меньше, чем
// весь список — работаем с остатком; список ИЗ ОДНИХ таких оставляем как есть, чтобы отказ пришёл
// от prepareHysteria с внятной причиной, а не «no servers».
function runnableServers(ctx) {
	let servers = orderedServers(ctx);
	if (ctx.hysteriaInstalled == null || ctx.hysteriaInstalled())
		return servers;
	let rest = filter(servers, function(s) { return !isHysteria(s); });
	return (length(rest) > 0) ? rest : servers;
}

// Failover по приоритету: идём по порядку, для каждого кандидата ctx.probeServer поднимает эфемерный
// туннель и гоняет реальную пробу связности; первый прошедший — активный. Имя-агностично (только
// порядок + результат пробы), работает на любой подписке. Если ни один не прошёл — фолбэк на servers[0]
// (kill-switch должен остаться, а watchdog разберётся дальше). Возврат: { server, probed }.
function selectWorking(ctx) {
	let servers = runnableServers(ctx);
	if (length(servers) == 0)
		return null;
	let cap = ctx.failoverCap ? ctx.failoverCap() : 0;
	let n = (cap > 0 && cap < length(servers)) ? cap : length(servers);
	for (let i = 0; i < n; i++) {
		if (ctx.probeServer(servers[i])) {
			ctx.setSelected(servers[i].tag);
			return { server: servers[i], probed: true };
		}
	}
	ctx.setSelected(servers[0].tag);
	return { server: servers[0], probed: false };
}

export { orderedServers, selectBest, selectWorking };
