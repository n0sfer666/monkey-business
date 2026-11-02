import { refKey, serverRef } from '../lib/availability.uc';
import { isTrue } from "../lib/val.uc";
import { serverId, serverSub, activeSubId, selectError } from "../lib/subs.uc";
import { isHysteria } from "../generator/hysteria.uc";
import { candidates, selectWorking } from "./select.uc";
import { generateJson } from "../generator/xray.uc";
import { prepareHysteria } from "./hysteria.uc";
import { configApply, genConfig } from "./handlers.uc";

function findIndex(servers, id, ref) {
	let typed = type(ref) == 'object' && length(keys(ref)), key = typed ? refKey(ref) : null;
	if ((ref != null && type(ref) != 'object') || (typed && key == null)) return -3;
	let found = -1;
	for (let i = 0; i < length(servers); i++)
		if (typed ? refKey(serverRef(servers[i])) == key : serverId(servers[i]) == id) {
			if (found >= 0) return -2;
			found = i;
		}
	return found;
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

function connectAtomic(ctx, args) {
	let id = args != null ? args.id : null, servers = ctx.getServers(), at = findIndex(servers, id, args != null ? args.server_ref : null);
	if (at < 0) return { error: at == -2 ? 'identity_conflict' : at == -3 ? 'invalid_ref' : 'unknown server' };
	let previousSub = ctx.getGlobal().active_sub || '', active = activeSubId(ctx.getSubscriptions(), previousSub);
	let target = servers[at], error = targetError(ctx, target, active);
	if (error != null) return { error: error };
	let desiredSub = serverSub(target) != null ? serverSub(target) : previousSub;
	let ordered = moveFirst(servers, at), fence = ctx.runtimeFence();
	let proposed = { ...ctx, getServers: function() { return ordered; },
		getGlobal: function() { return { ...ctx.getGlobal(), active_sub: desiredSub }; }, setSelected: function() {} };
	let selection = null;
	if (isTrue(ctx.getGlobal().enabled)) {
		selection = selectWorking(proposed, ctx.defaultDeadline ? ctx.defaultDeadline() - ctx.applyBudget() : ctx.now() + 45);
		if (selection == null || selection.error != null) return { error: selection != null ? selection.error : 'no_working_server' };
	}
	return ctx.withMutation(function() {
		ctx.refresh();
		if (ctx.runtimeFence() != fence || sprintf('%J', ctx.getServers()) != sprintf('%J', servers)) return { error: 'runtime_conflict' };
		let before = ctx.routingSnapshot();
		if (before.error != null) return { error: before.error };
		let error = targetError(ctx, target, active);
		if (error != null) return { error: error };
		if (!ctx.setPriority(ordered, desiredSub)) return { error: 'order_commit_failed' };
		if (selection == null) return { ok: true, skipped: 'disabled', server_id: serverId(target), server_ref: serverRef(target) };
		error = prepareHysteria(ctx, selection.server);
		if (error == null) {
			let applied = genConfig(ctx, selection.server);
			error = ctx.applyConfig(generateJson(applied), false, applied);
		}
		if (error != null) {
			let restored = ctx.setPriority(servers, previousSub);
			if (ctx.restoreRouting(before) != null) restored = false;
			if (restored && ctx.finishRouting(before) != null) restored = false;
			return { error: restored ? error : 'rollback_failed' };
		}
		ctx.setSelected(serverId(selection.server));
		if (desiredSub != previousSub) ctx.clearAutoswitch();
		return { ok: true, server: selection.server.tag, server_id: serverId(selection.server), server_ref: serverRef(selection.server), probed: true };
	});
}

function serverConnect(ctx, args) {
	if (ctx.setPriority != null) return connectAtomic(ctx, args);
	let id = (args != null) ? args.id : null;
	let servers = ctx.getServers();
	let at = findIndex(servers, id, args != null ? args.server_ref : null);
	if (at == -2 || at == -3) return { error: at == -2 ? 'identity_conflict' : 'invalid_ref' };
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
