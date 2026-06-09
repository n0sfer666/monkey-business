// Чистые rpcd-хендлеры. Зависимости (uci/ubus/сеть/файлы) инкапсулированы в `ctx` —
// это держит логику host-тестируемой. Рантайм-привязка ctx — в
// root/usr/share/rpcd/ucode/monkey-business.uc.
//
// Контракт ctx:
//   getGlobal() -> { enabled, routing_mode, local_region, tproxy_port, custom_direct, custom_proxy, ... }
//   getDns() -> { mode, direct_dns, doh_url }   getAntiDpi() -> { default_fingerprint, xhttp_padding }
//   getSubscription() -> { url, used_upload, used_download, total, expire, ... }
//   getServers() -> [server, ...]      setServers(arr)
//   getSelectedServer() -> server|null   setSelected(tag)
//   setSubscriptionUrl(url)   setUserinfo({used_upload,used_download,total,expire})
//   fetchSubscription(url) -> { body, userinfo }|null   pingServer(server) -> int(ms)|null
//   applyConfig(jsonStr) -> errString|null (валидирует + запускает)   stopService()
//   serviceRunning() -> bool   setEnabled(bool)   updateGeo() -> { status }

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

// "upload=0; download=123; total=456; expire=789" -> объект (значения строками)
function parseUserinfo(s) {
	let out = { used_upload: "", used_download: "", total: "", expire: "" };
	if (type(s) != "string" || trim(s) == "")
		return out;
	for (let part in split(s, ";")) {
		let kv = split(trim(part), "=");
		if (length(kv) != 2)
			continue;
		let k = trim(kv[0]), v = trim(kv[1]);
		if (k == "upload") out.used_upload = v;
		else if (k == "download") out.used_download = v;
		else if (k == "total") out.total = v;
		else if (k == "expire") out.expire = v;
	}
	return out;
}

function prio(s) {
	let p = s.priority;
	if (p == null)
		return 999;
	if (type(p) == "string" && trim(p) == "")
		return 999;
	return int(p);
}

function sortedServers(ctx) {
	let arr = ctx.getServers();
	return sort(arr, function(a, b) { return prio(a) - prio(b); });
}

// первый доступный по приоритету (tcpPing); нет живых -> первый; фиксирует selected
function selectBest(ctx) {
	let servers = sortedServers(ctx);
	if (length(servers) == 0)
		return null;
	let chosen = null;
	for (let s in servers)
		if (ctx.pingServer(s) != null) { chosen = s; break; }
	if (chosen == null)
		chosen = servers[0];
	ctx.setSelected(chosen.tag);
	return chosen;
}

function ensureSelected(ctx) {
	let s = ctx.getSelectedServer();
	return (s != null) ? s : selectBest(ctx);
}

function genConfig(ctx, server) {
	return {
		global: ctx.getGlobal(),
		server: server,
		dns: ctx.getDns(),
		anti_dpi: ctx.getAntiDpi(),
	};
}

function status(ctx) {
	let g = ctx.getGlobal();
	let s = ctx.getSelectedServer();
	let sub = ctx.getSubscription();
	return {
		enabled: isTrue(g.enabled),
		running: ctx.serviceRunning(),
		server: (s != null) ? s.tag : null,
		routing_mode: g.routing_mode,
		traffic: {
			used_upload: sub.used_upload || "",
			used_download: sub.used_download || "",
			total: sub.total || "",
			expire: sub.expire || "",
		},
	};
}

function serversList(ctx) {
	let out = [];
	for (let s in sortedServers(ctx))
		push(out, {
			tag: s.tag,
			address: s.address,
			port: s.port,
			security: s.security,
			transport: s.transport.type,
			priority: prio(s),
			uuid_masked: maskUuid(s.uuid),
		});
	return { servers: out };
}

function subscriptionUpdate(ctx, args) {
	let url = (args != null && args.url != null && args.url != "") ? args.url : ctx.getSubscription().url;
	if (url == null || url == "")
		return { error: "no subscription url" };

	let resp = ctx.fetchSubscription(url);
	if (resp == null || resp.body == null)
		return { error: "fetch failed", kept: length(ctx.getServers()) };

	let res = parse(resp.body);
	if (length(res.servers) == 0)
		return { error: "no servers parsed", format: res.format, kept: length(ctx.getServers()) };

	let i = 0;
	for (let sv in res.servers) { sv.priority = i; i++; }
	ctx.setServers(res.servers);
	ctx.setSubscriptionUrl(url);
	if (resp.userinfo != null && resp.userinfo != "")
		ctx.setUserinfo(parseUserinfo(resp.userinfo));
	selectBest(ctx);
	return { format: res.format, added: length(res.servers), errors: res.errors };
}

function serversPing(ctx) {
	let results = [];
	let best = null, bestMs = null;
	for (let s in sortedServers(ctx)) {
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
	let s = ensureSelected(ctx);
	if (s == null)
		return { error: "no servers — add a subscription or a manual server first" };
	let jsonStr = generateJson(genConfig(ctx, s));
	let err = ctx.applyConfig(jsonStr);
	if (err != null)
		return { error: err };
	return { ok: true, server: s.tag, bytes: length(jsonStr) };
}

function serviceToggle(ctx, args) {
	let on = (args != null) && isTrue(args.enabled);
	if (!on) {
		ctx.setEnabled(false);
		ctx.stopService();
		return { enabled: false };
	}
	let s = ensureSelected(ctx);
	if (s == null)
		return { error: "no servers — add a subscription first", enabled: false };
	let jsonStr = generateJson(genConfig(ctx, s));
	let err = ctx.applyConfig(jsonStr);
	if (err != null)
		return { error: err, enabled: false };
	ctx.setEnabled(true);
	return { enabled: true, server: s.tag };
}

function geoUpdate(ctx) {
	return ctx.updateGeo();
}

export { status, serversList, subscriptionUpdate, serversPing, configApply, serviceToggle, geoUpdate, maskUuid, parseUserinfo, selectBest };
