// Генератор Xray-конфига из структуры (как из UCI) + нормализованного server-объекта.
// Вход: { global, server, dns? }. Выход: generate() -> object, generateJson() -> string.
//
// global: { tproxy_port, routing_mode, local_region, log_level, ... }
//   routing_mode: "bypass-local" | "global" | "gfwlist"
// server: контракт из src/parser/subscription.uc
// DNS/anti-DPI расширяются на этапе 4 (T9).

const GEOSITE_REGION = { ru: "category-ru", cn: "cn", ir: "category-ir" };

function geositeRegion(region) {
	return GEOSITE_REGION[region] || region;
}

function isTrue(v) {
	return v == true || v == "1" || v == 1;
}

const SOCKS_TEST_PORT = 10808;

function buildInbound(g) {
	return {
		tag: "tproxy-in",
		port: g.tproxy_port || 12345,
		protocol: "dokodemo-door",
		settings: { network: "tcp,udp", followRedirect: true },
		streamSettings: { sockopt: { tproxy: "tproxy" } },
		sniffing: { enabled: true, destOverride: ["http", "tls", "quic"], routeOnly: true },
	};
}

// Локальный SOCKS-inbound (только 127.0.0.1) для проверки сплита: запрос через него идёт по тем
// же правилам маршрутизации, что и TPROXY-трафик. Включается флагом config.test_socks.
function buildSocksTestInbound() {
	return {
		tag: "socks-test",
		listen: "127.0.0.1",
		port: SOCKS_TEST_PORT,
		protocol: "socks",
		settings: { udp: false },
		sniffing: { enabled: true, destOverride: ["http", "tls"], routeOnly: false },
	};
}

const DNS_INBOUND_PORT = 5300;

// Прозрачный DNS: клиентский :53 редиректится firewall'ом сюда, трафик уходит в dns-аутбаунд ->
// dns-модуль xray применяет сплит (локальный регион direct / остальное DoH в туннеле). Без этого
// инбаунда клиентский UDP 53 ушёл бы под общий TPROXY и не резолвился. Включается config.dns_transparent.
function buildDnsInbound(port, dns) {
	return {
		tag: "dns-in",
		listen: "0.0.0.0",
		port: port,
		protocol: "dokodemo-door",
		settings: { address: dns.direct_dns || "77.88.8.8", port: 53, network: "tcp,udp" },
	};
}

function buildStreamSettings(s, opts) {
	opts = opts || {};
	let ss = { network: s.transport.type };
	let t = s.transport;
	if (t.type == "xhttp") {
		ss.xhttpSettings = { path: t.path, host: t.host, mode: t.mode };
		if (isTrue(opts.xhttpPadding))
			ss.xhttpSettings.xPaddingBytes = "100-1000";
	}
	else if (t.type == "ws")
		ss.wsSettings = { path: t.path, headers: { Host: t.host } };
	else if (t.type == "httpupgrade")
		ss.httpupgradeSettings = { path: t.path, host: t.host };
	else if (t.type == "grpc")
		ss.grpcSettings = { serviceName: t.serviceName };

	if (s.security == "reality") {
		ss.security = "reality";
		ss.realitySettings = {
			serverName: s.sni,
			fingerprint: s.fingerprint,
			publicKey: s.reality.publicKey,
			shortId: s.reality.shortId,
			spiderX: s.reality.spiderX,
		};
	} else if (s.security == "tls") {
		ss.security = "tls";
		ss.tlsSettings = { serverName: s.sni, fingerprint: s.fingerprint, alpn: s.alpn };
	} else {
		ss.security = "none";
	}
	return ss;
}

function buildProxyOutbound(s, opts) {
	let user = { id: s.uuid, encryption: s.encryption };
	if (s.flow != null && s.flow != "")
		user.flow = s.flow;
	return {
		tag: "proxy",
		protocol: "vless",
		settings: { vnext: [{ address: s.address, port: s.port, users: [user] }] },
		streamSettings: buildStreamSettings(s, opts),
	};
}

function isIpLike(t) {
	if (match(t, /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(\/[0-9]+)?$/) != null)
		return true;
	if (index(t, ":") >= 0 && match(t, /^[0-9a-fA-F:]+(\/[0-9]+)?$/) != null)
		return true;
	return false;
}

// Split-DNS: локальный регион резолвится напрямую, остальное — через DoH в туннеле.
// Домен самого VPN-сервера всегда резолвится напрямую (full:<домен>), иначе bootstrap-дедлок:
// поднять туннель -> нужен IP сервера -> его резолв ушёл бы в ещё не поднятый туннель.
function buildDns(dns, region, ipv6Blocked, server) {
	let queryStrategy = isTrue(ipv6Blocked) ? "UseIPv4" : "UseIP";
	let directDns = dns.direct_dns || "77.88.8.8";
	let doh = dns.doh_url || "https://1.1.1.1/dns-query";
	let serverDomain = (server != null && server.address != null && !isIpLike(server.address))
		? server.address : null;
	// "doh": весь DNS через DoH в туннеле, но домен сервера всё равно резолвим напрямую (bootstrap).
	if (dns.mode == "doh") {
		let servers = [];
		if (serverDomain != null)
			push(servers, { address: directDns, domains: ["full:" + serverDomain], skipFallback: true });
		push(servers, doh);
		return { servers: servers, queryStrategy: queryStrategy };
	}
	// split: домен сервера + локальный регион + private резолвятся напрямую, остальное — через DoH.
	// region "other": geosite:other невалидна -> direct только private, сплит доменов — через custom-списки.
	let directDomains = (region == "other")
		? ["geosite:private"]
		: ["geosite:private", "geosite:" + geositeRegion(region)];
	if (serverDomain != null)
		unshift(directDomains, "full:" + serverDomain);
	return {
		servers: [
			{ address: directDns, domains: directDomains, skipFallback: true },
			doh,
		],
		queryStrategy: queryStrategy,
	};
}

// строки (через \n или ,) -> { domains:[...], ips:[...] }; поддержка geoip:/geosite:
function classifyList(str) {
	let domains = [], ips = [];
	if (str == null || str == "")
		return { domains: domains, ips: ips };
	let norm = replace(str, ",", "\n");
	for (let line in split(norm, "\n")) {
		let t = trim(line);
		if (t == "" || substr(t, 0, 1) == "#")
			continue;
		if (index(t, "geosite:") == 0)
			push(domains, t);
		else if (index(t, "geoip:") == 0)
			push(ips, t);
		else if (substr(t, 0, 2) == "*." && length(t) > 2)
			push(domains, "domain:" + substr(t, 2));
		else if (isIpLike(t))
			push(ips, t);
		else
			push(domains, t);
	}
	return { domains: domains, ips: ips };
}

function customRules(g) {
	let rules = [];
	let cd = classifyList(g.custom_direct);
	let cp = classifyList(g.custom_proxy);
	if (length(cd.domains)) push(rules, { type: "field", domain: cd.domains, outboundTag: "direct" });
	if (length(cd.ips)) push(rules, { type: "field", ip: cd.ips, outboundTag: "direct" });
	if (length(cp.domains)) push(rules, { type: "field", domain: cp.domains, outboundTag: "proxy" });
	if (length(cp.ips)) push(rules, { type: "field", ip: cp.ips, outboundTag: "proxy" });
	return rules;
}

function buildRouting(g, directDns) {
	let region = g.local_region || "ru";
	let mode = g.routing_mode || "bypass-local";
	// local_region "other": нет geo-категории региона (geosite:other/geoip:other невалидны,
	// xray -test падает) -> geo-правила региона опускаются; сплит задаётся custom-списками,
	// private всегда direct, судьба «остального» — по routing_mode.
	let other = (region == "other");
	let rules = [];

	// custom direct/proxy — только в split-tunnel (не в global), ПЕРЕД правилами режима.
	// Должны идти ДО ipv6-block: явный whitelist (в т.ч. IPv6) перекрывает блок ::/0.
	if (mode != "global")
		for (let r in customRules(g))
			push(rules, r);

	// direct_dns-резолвер жёстко в direct: bootstrap туннеля резолвит домен сервера через него,
	// и этот резолв НЕ должен уходить в ещё не поднятый туннель (не полагаемся на geoip:ru — geoip.dat
	// может быть не загружен на свежей установке).
	if (directDns != null && directDns != "" && isIpLike(directDns))
		push(rules, { type: "field", ip: [directDns], outboundTag: "direct" });

	if (isTrue(g.ipv6_block))
		push(rules, { type: "field", ip: ["::/0"], outboundTag: "block" });

	let modeRules;
	if (mode == "global") {
		modeRules = [
			{ type: "field", ip: ["geoip:private"], outboundTag: "direct" },
			{ type: "field", network: "tcp,udp", outboundTag: "proxy" },
		];
	} else if (mode == "gfwlist") {
		modeRules = [ { type: "field", ip: ["geoip:private"], outboundTag: "direct" } ];
		if (!other)
			push(modeRules, { type: "field", domain: ["geosite:geolocation-!" + region], outboundTag: "proxy" });
		push(modeRules, { type: "field", network: "tcp,udp", outboundTag: "direct" });
	} else {
		let directIps = other ? ["geoip:private"] : ["geoip:private", "geoip:" + region];
		let directDomains = other ? ["geosite:private"] : ["geosite:private", "geosite:" + geositeRegion(region)];
		modeRules = [
			{ type: "field", ip: directIps, outboundTag: "direct" },
			{ type: "field", domain: directDomains, outboundTag: "direct" },
			{ type: "field", network: "tcp,udp", outboundTag: "proxy" },
		];
	}
	for (let r in modeRules)
		push(rules, r);

	return { domainStrategy: "IPIfNonMatch", rules: rules };
}

function generate(config) {
	let g = config.global || {};
	let s = config.server;
	if (s == null)
		die("generate: missing server");

	let anti = config.anti_dpi || {};
	let opts = { xhttpPadding: anti.xhttp_padding };

	let inbounds = [buildInbound(g)];
	if (isTrue(config.test_socks))
		push(inbounds, buildSocksTestInbound());

	let outbounds = [
		buildProxyOutbound(s, opts),
		{ tag: "direct", protocol: "freedom", settings: {} },
		{ tag: "block", protocol: "blackhole", settings: {} },
	];

	let routing = buildRouting(g, config.dns != null ? (config.dns.direct_dns || "77.88.8.8") : null);

	// прозрачный DNS: dns-инбаунд -> dns-аутбаунд (резолв через dns-модуль со сплитом).
	// правило dns-in ставится ПЕРВЫМ, чтобы DNS всегда уходил в dns-out (а не под общие правила).
	if (isTrue(config.dns_transparent)) {
		push(inbounds, buildDnsInbound(config.dns_port || DNS_INBOUND_PORT, config.dns || {}));
		push(outbounds, { tag: "dns-out", protocol: "dns", settings: {} });
		unshift(routing.rules, { type: "field", inboundTag: ["dns-in"], outboundTag: "dns-out" });
	}

	let out = {
		log: { loglevel: g.log_level || "warning" },
		inbounds: inbounds,
		outbounds: outbounds,
		routing: routing,
	};

	if (config.dns != null)
		out.dns = buildDns(config.dns, g.local_region || "ru", g.ipv6_block, s);

	return out;
}

// Лёгкий конфиг для эфемерной пробы одного кандидата: socks-inbound -> proxy(candidate), без tproxy/
// firewall/kill-switch. Резолв домена сервера идёт напрямую (direct_dns в direct + full:<домен> в dns),
// всё остальное из socks -> в туннель. Проба (curl через socks к иностранному IP) проверяет реальный
// проход трафика, а не только TCP-connect. probe_port по умолчанию 10809 (боевой socks-test = 10808).
function generateProbe(config) {
	let s = config.server;
	if (s == null)
		die("generateProbe: missing server");
	let g = config.global || {};
	let dns = config.dns || {};
	let region = g.local_region || "ru";
	let directDns = dns.direct_dns || "77.88.8.8";
	return {
		log: { loglevel: "warning" },
		inbounds: [{
			tag: "probe", listen: "127.0.0.1", port: config.probe_port || 10809,
			protocol: "socks", settings: { udp: false },
		}],
		outbounds: [
			buildProxyOutbound(s, {}),
			{ tag: "direct", protocol: "freedom", settings: {} },
		],
		routing: { domainStrategy: "IPIfNonMatch", rules: [
			{ type: "field", ip: [directDns], outboundTag: "direct" },
			{ type: "field", inboundTag: ["probe"], outboundTag: "proxy" },
		] },
		dns: buildDns(dns, region, g.ipv6_block, s),
	};
}

function generateJson(config) {
	return sprintf("%.J", generate(config));
}

export { generate, generateJson, generateProbe, buildRouting, buildStreamSettings, buildDns };
