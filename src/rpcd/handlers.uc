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
//   serviceRunning() -> bool   setEnabled(bool)   updateGeo(args) -> { status }
//   setCustomRouting(direct, proxy)   geoStatus() -> { state, geoip, geosite }
//   geoInstall(which) -> { ok, detail }   checkExit(domain) -> { ip, country, code }|{ error }

import { parse } from "../parser/subscription.uc";
import { generateJson } from "../generator/xray.uc";

function isTrue(v) {
	return v == true || v == "1" || v == 1;
}

function maskUuid(u) {
	if (u == null || length(u) < 12)
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

// Failover по приоритету: идём по порядку, для каждого кандидата ctx.probeServer поднимает эфемерный
// туннель и гоняет реальную пробу связности; первый прошедший — активный. Имя-агностично (только
// порядок + результат пробы), работает на любой подписке. Если ни один не прошёл — фолбэк на servers[0]
// (kill-switch должен остаться, а watchdog разберётся дальше). Возврат: { server, probed }.
function selectWorking(ctx) {
	let servers = orderedServers(ctx);
	if (length(servers) == 0)
		return null;
	let cap = ctx.failoverCap ? ctx.failoverCap() : length(servers);
	let n = (length(servers) < cap) ? length(servers) : cap;
	for (let i = 0; i < n; i++) {
		if (ctx.probeServer(servers[i])) {
			ctx.setSelected(servers[i].tag);
			return { server: servers[i], probed: true };
		}
	}
	ctx.setSelected(servers[0].tag);
	return { server: servers[0], probed: false };
}

function genConfig(ctx, server) {
	return {
		global: ctx.getGlobal(),
		server: server,
		dns: ctx.getDns(),
		anti_dpi: ctx.getAntiDpi(),
		test_socks: true,
		dns_transparent: true,
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
	let i = 0;
	for (let s in orderedServers(ctx)) {
		push(out, {
			tag: s.tag,
			address: s.address,
			port: s.port,
			security: s.security,
			transport: (s.transport != null) ? s.transport.type : "tcp",
			priority: i,
			uuid_masked: maskUuid(s.uuid),
		});
		i++;
	}
	return { servers: out };
}

function serverKey(s) {
	let tr = (type(s.transport) == "object") ? s.transport : {};
	let re = (type(s.reality) == "object") ? s.reality : {};
	let alpn = (type(s.alpn) == "array") ? join(",", s.alpn) : "";
	return join("|", [
		s.tag || "",
		s.address || "", "" + (s.port || ""), s.uuid || "",
		s.security || "", s.flow || "", s.sni || "", s.fingerprint || "", alpn,
		re.publicKey || "", re.shortId || "", re.spiderX || "",
		tr.type || "", tr.path || "", tr.host || "", tr.mode || "", tr.serviceName || "",
	]);
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

	// СОХРАНИТЬ РУЧНОЙ ПОРЯДОК: выдать существующие серверы в их текущем порядке (матч по ключу,
	// данные обновляются из свежей подписки), новые — в конец. Иначе re-fetch (Save&Apply/
	// автообновление) сбрасывал бы drag-сортировку к порядку подписки.
	let byKey = {};
	for (let sv in res.servers)
		byKey[serverKey(sv)] = sv;
	let ordered = [];
	let used = {};
	for (let old in ctx.getServers()) {
		let k = serverKey(old);
		if (byKey[k] != null && used[k] == null) {
			push(ordered, byKey[k]);
			used[k] = true;
		}
	}
	for (let sv in res.servers) {
		let k = serverKey(sv);
		if (used[k] == null) {
			push(ordered, sv);
			used[k] = true;
		}
	}
	ctx.setServers(ordered);
	ctx.setSubscriptionUrl(url);
	if (resp.userinfo != null && resp.userinfo != "")
		ctx.setUserinfo(parseUserinfo(resp.userinfo));
	selectBest(ctx);
	return { format: res.format, added: length(res.servers), errors: res.errors };
}

function serversPing(ctx) {
	let results = [];
	let best = null, bestMs = null;
	for (let s in orderedServers(ctx)) {
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
	let sel = selectWorking(ctx);
	if (sel == null)
		return { error: "no servers — add a subscription or a manual server first" };
	let jsonStr = generateJson(genConfig(ctx, sel.server));
	let err = ctx.applyConfig(jsonStr);
	if (err != null)
		return { error: err };
	return { ok: true, server: sel.server.tag, probed: sel.probed, bytes: length(jsonStr) };
}

function serviceToggle(ctx, args) {
	let on = (args != null) && isTrue(args.enabled);
	if (!on) {
		ctx.setEnabled(false);
		ctx.stopService();
		return { enabled: false };
	}
	let sel = selectWorking(ctx);
	if (sel == null)
		return { error: "no servers — add a subscription first", enabled: false };
	let jsonStr = generateJson(genConfig(ctx, sel.server));
	let err = ctx.applyConfig(jsonStr);
	if (err != null)
		return { error: err, enabled: false };
	ctx.setEnabled(true);
	return { enabled: true, server: sel.server.tag, probed: sel.probed };
}

function geoUpdate(ctx, args) {
	return ctx.updateGeo(args);
}

// Записать custom direct/proxy в UCI (commit на стороне сервера, без LuCI-стейджинга) и применить.
function setRouting(ctx, args) {
	let direct = (args != null && args.direct != null) ? args.direct : "";
	let proxy = (args != null && args.proxy != null) ? args.proxy : "";
	ctx.setCustomRouting(direct, proxy);
	return configApply(ctx);
}

function geoStatus(ctx) {
	return ctx.geoStatus();
}

function geoInstall(ctx, args) {
	let which = (args != null) ? args.which : null;
	if (which != "geoip" && which != "geosite")
		return { error: "bad which (geoip|geosite)" };
	return ctx.geoInstall(which);
}

// Проверка сплита: запрос к гео-сервису через тестовый SOCKS-inbound -> по каким правилам ушёл
// (proxy/direct), какой выходной IP/страна. domain = гео-сервис (по умолчанию ip-api.com).
function checkExit(ctx, args) {
	let domain = (args != null) ? args.domain : null;
	return ctx.checkExit(domain);
}

export { status, serversList, subscriptionUpdate, serversPing, configApply, serviceToggle, geoUpdate, setRouting, geoStatus, geoInstall, checkExit, maskUuid, parseUserinfo, selectBest, selectWorking };
