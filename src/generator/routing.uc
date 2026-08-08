// Правила маршрутизации: режимы сплита, custom-списки пользователя, порядок правил.
// Порядок здесь — это и есть сплит, поэтому он собран в одном месте.

import { isTrueByDefault, isIpLike } from "../lib/val.uc";

const GEOSITE_REGION = { ru: "category-ru", cn: "cn", ir: "category-ir" };

function geositeRegion(region) {
	return GEOSITE_REGION[region] || region;
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

function modeRules(mode, region, other) {
	if (mode == "global")
		return [
			{ type: "field", ip: ["geoip:private"], outboundTag: "direct" },
			{ type: "field", network: "tcp,udp", outboundTag: "proxy" },
		];
	if (mode == "gfwlist") {
		let rules = [ { type: "field", ip: ["geoip:private"], outboundTag: "direct" } ];
		if (!other)
			push(rules, { type: "field", domain: ["geosite:geolocation-!" + region], outboundTag: "proxy" });
		push(rules, { type: "field", network: "tcp,udp", outboundTag: "direct" });
		return rules;
	}
	let directIps = other ? ["geoip:private"] : ["geoip:private", "geoip:" + region];
	let directDomains = other ? ["geosite:private"] : ["geosite:private", "geosite:" + geositeRegion(region)];
	return [
		{ type: "field", ip: directIps, outboundTag: "direct" },
		{ type: "field", domain: directDomains, outboundTag: "direct" },
		{ type: "field", network: "tcp,udp", outboundTag: "proxy" },
	];
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

	// Отсутствие опции = блок ВКЛЮЧЁН: дефолтный конфиг её содержит, и пропасть она может только
	// одним способом — LuCI стёр её как совпавшую с default. Читать это как «человек выключил»
	// значит снимать защиту от утечки по факту чужой особенности формы.
	if (isTrueByDefault(g.ipv6_block))
		push(rules, { type: "field", ip: ["::/0"], outboundTag: "block" });

	for (let r in modeRules(mode, region, other))
		push(rules, r);

	return { domainStrategy: "IPIfNonMatch", rules: rules };
}

export { buildRouting, geositeRegion };
