// Чистые rpcd-хендлеры. Зависимости (uci/ubus/сеть/файлы) инкапсулированы в `ctx` —
// это держит логику host-тестируемой. Рантайм-привязка ctx — в
// root/usr/share/rpcd/ucode/monkey-business.uc.
//
// Контракт ctx:
//   getGlobal() -> { enabled, routing_mode, local_region, tproxy_port, ... }
//   getSubscription() -> { url, ... }
//   getServers() -> [server, ...]      setServers(arr)
//   getSelectedServer() -> server|null
//   fetchSubscription(url) -> string|null   pingServer(server) -> int(ms)|null
//   applyConfig(jsonStr)                serviceRunning() -> bool   setEnabled(bool)
//   updateGeo() -> { status, ... }

import { parse } from "../parser/subscription.uc";
import { generateJson } from "../generator/xray.uc";

function isTrue(v) {
	return v == true || v == "1" || v == 1;
}

function maskUuid(u) {
	if (u == null || length(u) < 8)
		return "****";
	return substr(u, 0, 4) + ".." + substr(u, length(u) - 4);
}

function status(ctx) {
	let g = ctx.getGlobal();
	let s = ctx.getSelectedServer();
	return {
		enabled: isTrue(g.enabled),
		running: ctx.serviceRunning(),
		server: (s != null) ? s.tag : null,
		routing_mode: g.routing_mode,
	};
}

function serversList(ctx) {
	let out = [];
	for (let s in ctx.getServers())
		push(out, {
			tag: s.tag,
			address: s.address,
			port: s.port,
			security: s.security,
			transport: s.transport.type,
			uuid_masked: maskUuid(s.uuid),
		});
	return { servers: out };
}

function subscriptionUpdate(ctx, args) {
	let url = (args != null && args.url != null && args.url != "") ? args.url : ctx.getSubscription().url;
	if (url == null || url == "")
		return { error: "no subscription url" };

	let raw = ctx.fetchSubscription(url);
	if (raw == null)
		return { error: "fetch failed", kept: length(ctx.getServers()) };

	let res = parse(raw);
	if (length(res.servers) == 0)
		return { error: "no servers parsed", format: res.format, kept: length(ctx.getServers()) };

	ctx.setServers(res.servers);
	return { format: res.format, added: length(res.servers), errors: res.errors };
}

function serversPing(ctx) {
	let results = [];
	let best = null;
	let bestMs = null;
	for (let s in ctx.getServers()) {
		let ms = ctx.pingServer(s);
		push(results, { tag: s.tag, latency_ms: ms });
		if (ms != null && (bestMs == null || ms < bestMs)) {
			bestMs = ms;
			best = s.tag;
		}
	}
	return { results: results, best: best };
}

function configApply(ctx) {
	let g = ctx.getGlobal();
	let s = ctx.getSelectedServer();
	if (s == null)
		return { error: "no server selected" };
	let jsonStr = generateJson({ global: g, server: s });
	ctx.applyConfig(jsonStr);
	return { ok: true, bytes: length(jsonStr) };
}

function serviceToggle(ctx, args) {
	let on = (args != null) && isTrue(args.enabled);
	ctx.setEnabled(on);
	return { enabled: on };
}

function geoUpdate(ctx) {
	return ctx.updateGeo();
}

export { status, serversList, subscriptionUpdate, serversPing, configApply, serviceToggle, geoUpdate, maskUuid };
