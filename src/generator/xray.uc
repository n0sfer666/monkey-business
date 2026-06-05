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

function buildInbound(g) {
	return {
		tag: "tproxy-in",
		port: g.tproxy_port || 12345,
		protocol: "dokodemo-door",
		settings: { network: "tcp,udp", followRedirect: true },
		streamSettings: { sockopt: { tproxy: "tproxy" } },
		sniffing: { enabled: true, destOverride: ["http", "tls", "quic"], routeOnly: false },
	};
}

function buildStreamSettings(s) {
	let ss = { network: s.transport.type };
	let t = s.transport;
	if (t.type == "xhttp")
		ss.xhttpSettings = { path: t.path, host: t.host, mode: t.mode };
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

function buildProxyOutbound(s) {
	let user = { id: s.uuid, encryption: s.encryption };
	if (s.flow != null && s.flow != "")
		user.flow = s.flow;
	return {
		tag: "proxy",
		protocol: "vless",
		settings: { vnext: [{ address: s.address, port: s.port, users: [user] }] },
		streamSettings: buildStreamSettings(s),
	};
}

function buildRouting(g) {
	let region = g.local_region || "ru";
	let mode = g.routing_mode || "bypass-local";
	let rules = [];

	if (mode == "global") {
		rules = [
			{ type: "field", ip: ["geoip:private"], outboundTag: "direct" },
			{ type: "field", network: "tcp,udp", outboundTag: "proxy" },
		];
	} else if (mode == "gfwlist") {
		rules = [
			{ type: "field", ip: ["geoip:private"], outboundTag: "direct" },
			{ type: "field", domain: ["geosite:geolocation-!" + region], outboundTag: "proxy" },
			{ type: "field", network: "tcp,udp", outboundTag: "direct" },
		];
	} else {
		rules = [
			{ type: "field", ip: ["geoip:private", "geoip:" + region], outboundTag: "direct" },
			{ type: "field", domain: ["geosite:private", "geosite:" + geositeRegion(region)], outboundTag: "direct" },
			{ type: "field", network: "tcp,udp", outboundTag: "proxy" },
		];
	}

	return { domainStrategy: "IPIfNonMatch", rules: rules };
}

function generate(config) {
	let g = config.global || {};
	let s = config.server;
	if (s == null)
		die("generate: missing server");

	return {
		log: { loglevel: g.log_level || "warning" },
		inbounds: [buildInbound(g)],
		outbounds: [
			buildProxyOutbound(s),
			{ tag: "direct", protocol: "freedom", settings: {} },
			{ tag: "block", protocol: "blackhole", settings: {} },
		],
		routing: buildRouting(g),
	};
}

function generateJson(config) {
	return sprintf("%.J", generate(config));
}

export { generate, generateJson, buildRouting, buildStreamSettings };
