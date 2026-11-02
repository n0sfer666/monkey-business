import { isHysteria } from "../generator/hysteria.uc";
import { serverId } from "../lib/subs.uc";

const PING_LIMIT_MS = 1000;

function pingView(pings, s) {
	if (isHysteria(s))
		return { latency_ms: null, na: true, auto_disabled: false };
	let p = pings[serverId(s)];
	let ms = (p != null) ? p.ms : null;
	return { latency_ms: ms, na: false, auto_disabled: p != null && (ms == null || ms > PING_LIMIT_MS) };
}

function measure(ctx, servers) {
	let known = {};
	for (let s in ctx.getServers())
		known[serverId(s)] = true;
	let pings = {};
	let old = ctx.getPings();
	for (let id in old)
		if (known[id])
			pings[id] = old[id];
	let tcp = filter(servers, function(s) { return !isHysteria(s); });
	if (length(tcp) == 0)
		return pings;
	let ms = ctx.pingServers(tcp, PING_LIMIT_MS);
	for (let i = 0; i < length(tcp); i++)
		pings[serverId(tcp[i])] = { ms: ms[i] };
	ctx.setPings(pings);
	return pings;
}

function reachable(ctx, servers) {
	let pings = measure(ctx, servers);
	let tcpOk = false;
	let ok = filter(servers, function(s) {
		let v = pingView(pings, s);
		if (!v.na && !v.auto_disabled)
			tcpOk = true;
		return !v.auto_disabled;
	});
	return tcpOk ? ok : servers;
}

export { PING_LIMIT_MS, pingView, measure, reachable };
