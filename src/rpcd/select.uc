// Выбор активного сервера и failover по приоритету. Отдельный файл: это единственное место, где
// решается, какой сервер получит трафик, и его цена — «интернета нет» при ошибке.

import { isHysteria } from "../generator/hysteria.uc";
import { isTrue } from "../lib/val.uc";
import { serverSub, serverId, subId, activeSubId, subAlive } from "../lib/subs.uc";
import { reachable } from "./latency.uc";

const PROBE_COST = 12;
const HYSTERIA_PROBE_COST = 15;

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
// selectWorking он лишь пре-фильтр с фолбэком на полный список.
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

// Failover по приоритету: кандидаты сначала проходят TCP-пинг (reachable; не прошёл ни один TCP —
// берутся все), затем по порядку для каждого ctx.probeServer поднимает эфемерный туннель и гоняет
// реальную пробу связности; первый прошедший — активный. Имя-агностично (только порядок + результат
// пробы), работает на любой подписке. Если ни один не прошёл — фолбэк на первого после пре-фильтра
// (kill-switch должен остаться, а watchdog разберётся дальше). Возврат: { server, probed }.
// deadline (epoch, 0 = без потолка): проба, которая не успеет закончиться до него, не начинается.
function selectWorking(ctx, deadline) {
	let all = runnableServers(ctx);
	if (length(all) == 0)
		return null;
	let servers = reachable(ctx, all);
	let cap = ctx.failoverCap ? ctx.failoverCap() : 0;
	let n = (cap > 0 && cap < length(servers)) ? cap : length(servers);
	for (let i = 0; i < n; i++) {
		if (deadline > 0 && ctx.now() + probeCost(servers[i]) > deadline)
			break;
		if (ctx.probeServer(servers[i])) {
			ctx.setSelected(serverId(servers[i]));
			return { server: servers[i], probed: true };
		}
	}
	ctx.setSelected(serverId(servers[0]));
	return { server: servers[0], probed: false };
}

export { probeCost, grouped, candidates, listedServers, orderedServers, selectBest, selectWorking };
