// DNS-секция xray. Отдельный файл, потому что тут своя развилка (split/doh) и своё
// bootstrap-правило, которое обязано пережить любые изменения правил маршрутизации.

import { isTrueByDefault, isIpLike } from "../lib/val.uc";
import { geositeRegion } from "./routing.uc";

// Split-DNS: локальный регион резолвится напрямую, остальное — через DoH в туннеле.
// Домен самого VPN-сервера всегда резолвится напрямую (full:<домен>), иначе bootstrap-дедлок:
// поднять туннель -> нужен IP сервера -> его резолв ушёл бы в ещё не поднятый туннель.
function buildDns(dns, region, ipv6Blocked, server) {
	// Как и в routing.uc: опции нет -> считаем, что блок включён (её стирает форма, а не человек).
	let queryStrategy = isTrueByDefault(ipv6Blocked) ? "UseIPv4" : "UseIP";
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

export { buildDns };
