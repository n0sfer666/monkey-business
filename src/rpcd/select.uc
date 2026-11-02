// Выбор активного сервера и failover по приоритету. Отдельный файл: это единственное место, где
// решается, какой сервер получит трафик, и его цена — «интернета нет» при ошибке.

import { isHysteria } from "../generator/hysteria.uc";
import { isTrue } from "../lib/val.uc";
import { serverSub, serverId, subId, activeSubId, subAlive } from "../lib/subs.uc";

const PROBE_COST = 30;
const HYSTERIA_PROBE_COST = 33;

function probeCost(s) {
	return isHysteria(s) ? HYSTERIA_PROBE_COST : PROBE_COST;
}

// Приоритет = сначала группа: активная подписка вместе с ручными, затем резервные подписки по их
// порядку; внутри группы — порядок секций UCI (drag-reorder в GridSection). Backend и UI уважают этот
// порядок; re-fetch его сохраняет (см. subscriptionUpdate).
function grouped(servers, subs, want) {
	let active = activeSubId(subs, want);
	let out = filter(servers, function(s) {
		let sub = serverSub(s);
		return sub == null || sub == active;
	});
	for (let sub in subs)
		if (subId(sub) != active)
			for (let s in servers)
				if (serverSub(s) == subId(sub))
					push(out, s);
	return out;
}

function candidates(servers, subs, want, now) {
	let active = activeSubId(subs, want);
	let dead = {};
	for (let sub in subs)
		if (subId(sub) != active && !subAlive(sub, now))
			dead[subId(sub)] = true;
	return filter(grouped(servers, subs, want), function(s) {
		let sub = serverSub(s);
		return !isTrue(s.disabled) && (sub == null || dead[sub] != true);
	});
}

function listedServers(ctx) {
	return grouped(ctx.getServers(), ctx.getSubscriptions(), ctx.getGlobal().active_sub);
}

function orderedServers(ctx) {
	return candidates(ctx.getServers(), ctx.getSubscriptions(), ctx.getGlobal().active_sub, time());
}

// Активный сервер = ПЕРВЫЙ по приоритету (порядок секций UCI = предпочтение пользователя).
// TCP-пинг здесь не используется (даёт ложные негативы даже на рабочих Reality-серверах): для
// selectWorking выполняет полные пробы без TCP-префильтра.
function selectBest(ctx) {
	let servers = orderedServers(ctx);
	if (length(servers) == 0)
		return null;
	let chosen = servers[0];
	ctx.setSelected(serverId(chosen));
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

// Проверка кандидатов в исходном порядке. TCP не исключает узлы и не является
// доказательством VPN. Первый успешный полный probe выбирается; если никто не
// подтверждён, работающий runtime сохраняется и вызывающий получает ошибку.
// deadline ограничивает начало следующих проб, cap — количество кандидатов.
function selectWorking(ctx, deadline) {
	let all = runnableServers(ctx);
	if (length(all) == 0)
		return null;
	let servers = all, expired = false;
	let cap = ctx.failoverCap ? ctx.failoverCap() : 0;
	let n = (cap > 0 && cap < length(servers)) ? cap : length(servers);
	for (let i = 0; i < n; i++) {
		if (deadline > 0 && ctx.now() + probeCost(servers[i]) > deadline) { expired = true; break; }
		if (ctx.probeServer(servers[i])) {
			ctx.setSelected(serverId(servers[i]));
			return { server: servers[i], probed: true };
		}
	}
	return { error: expired ? "probe_deadline" : "no_working_server" };
}

export { probeCost, grouped, candidates, listedServers, orderedServers, selectBest, selectWorking };
