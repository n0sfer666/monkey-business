// Генератор Xray-конфига из структуры (как из UCI) + нормализованного server-объекта.
// Вход: { global, server, dns? }. Выход: generate() -> object, generateJson() -> string.
//
// global: { tproxy_port, routing_mode, local_region, log_level, ... }
//   routing_mode: "bypass-local" | "global" | "gfwlist"
// server: контракт из src/parser/subscription.uc
//
// Сборка секций живёт рядом: inbounds.uc, outbounds.uc, routing.uc, dns.uc. Здесь — только их
// склейка в конфиг и порядок, в котором секции влияют друг на друга.

import { isTrue } from "../lib/val.uc";
import { buildInbound, buildSocksTestInbound, buildDnsInbound, DNS_INBOUND_PORT } from "./inbounds.uc";
import { buildProxyOutbound } from "./outbounds.uc";
import { buildRouting } from "./routing.uc";
import { buildDns } from "./dns.uc";

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
			// hysteria-кандидат пробуется через свой эфемерный клиент на отдельном socks-порту, чтобы
			// не трогать боевой 10810 работающего туннеля.
			buildProxyOutbound(s, { socksPort: config.hysteria_socks_port }),
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

export { generate, generateJson, generateProbe };
