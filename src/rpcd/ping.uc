// Замер latency по кнопкам UI: все серверы, серверы подписки, один сервер. Порядок и активный сервер
// не меняются.

import { listedServers } from "./select.uc";
import { measure, pingView } from "./latency.uc";
import { serverSub, serverId, findSub } from "../lib/subs.uc";

function view(pings, s) {
	let v = pingView(pings, s);
	v.id = serverId(s);
	v.tag = s.tag;
	return v;
}

function pingList(ctx, servers) {
	let pings = measure(ctx, servers);
	return map(servers, function(s) { return view(pings, s); });
}

function serversPing(ctx) {
	let results = pingList(ctx, listedServers(ctx));
	let best = null;
	for (let r in results)
		if (r.latency_ms != null && (best == null || r.latency_ms < best.latency_ms))
			best = r;
	return { results: results, best: (best != null) ? best.tag : null, best_id: (best != null) ? best.id : null };
}

function subscriptionPing(ctx, args) {
	let want = (args != null) ? args.sub : null;
	if (want == null || findSub(ctx.getSubscriptions(), want) == null)
		return { error: "unknown subscription" };
	let servers = filter(listedServers(ctx), function(s) { return serverSub(s) == want; });
	return { sub: want, results: pingList(ctx, servers) };
}

function serverPing(ctx, args) {
	let want = (args != null) ? args.id : null;
	for (let s in listedServers(ctx))
		if (serverId(s) == want)
			return pingList(ctx, [ s ])[0];
	return { error: "unknown server" };
}

export { serversPing, subscriptionPing, serverPing };
