import { isTrue } from "../lib/val.uc";
import { serverId, serverSub, activeSubId, selectError } from "../lib/subs.uc";
import { isHysteria } from "../generator/hysteria.uc";
import { candidates } from "./select.uc";
import { configApply } from "./handlers.uc";

function findIndex(servers, id) {
	for (let i = 0; i < length(servers); i++)
		if (serverId(servers[i]) == id)
			return i;
	return -1;
}

function moveFirst(servers, at) {
	let out = [ servers[at] ];
	for (let i = 0; i < length(servers); i++)
		if (i != at)
			push(out, servers[i]);
	return out;
}

function noClient(ctx, s) {
	return isHysteria(s) && ctx.hysteriaInstalled != null && !ctx.hysteriaInstalled();
}

function targetError(ctx, s, active) {
	if (isTrue(s.disabled))
		return "server is off: turn it on first";
	if (noClient(ctx, s))
		return "hysteria client is not installed: install it under Components first";
	let sub = serverSub(s);
	if (sub == null || sub == active)
		return null;
	return selectError(ctx.getSubscriptions(), sub, ctx.now());
}

function leads(ctx, servers, id, want) {
	let list = candidates(servers, ctx.getSubscriptions(), want, ctx.now());
	return length(list) > 0 && serverId(list[0]) == id;
}

function live(ctx) {
	return isTrue(ctx.getGlobal().enabled) && ctx.serviceRunning();
}

function serverConnect(ctx, args) {
	let id = (args != null) ? args.id : null;
	let servers = ctx.getServers();
	let at = findIndex(servers, id);
	if (at < 0)
		return { error: "unknown server" };
	let s = servers[at];
	let prevActive = ctx.getGlobal().active_sub || "";
	let active = activeSubId(ctx.getSubscriptions(), prevActive);
	let err = targetError(ctx, s, active);
	if (err != null)
		return { error: err };
	let sub = serverSub(s);
	let switching = sub != null && sub != active;
	let prevId = ctx.getSelectedId();
	if (!switching && prevId == id && live(ctx) && leads(ctx, servers, id, prevActive))
		return { ok: true, server_id: id, unchanged: true };
	if (!ctx.setServers(moveFirst(servers, at)))
		return { error: "could not save the server order (read-only config?)" };
	if (switching && !ctx.setActiveSub(sub)) {
		ctx.setServers(servers);
		return { error: "could not save the subscription choice (read-only config?)" };
	}
	let res = configApply(ctx);
	if (res.error != null) {
		ctx.setServers(servers);
		if (switching)
			ctx.setActiveSub(prevActive);
		ctx.setSelected(prevId);
		return res;
	}
	if (switching)
		ctx.clearAutoswitch();
	return res;
}

export { serverConnect };
