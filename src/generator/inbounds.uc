// Инбаунды xray: боевой TPROXY, локальный socks для проверки сплита, прозрачный DNS.

import { diagnosticPort, diagnosticCredentials } from "../lib/diagnostic.uc";

const SOCKS_TEST_PORT = 10808;
const DNS_INBOUND_PORT = 5300;

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
// же общим правилам сплита, что и TPROXY-трафик, без LAN-only corporate overrides.
// Не является health-путём. Включается флагом config.test_socks.
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

function buildDiagnosticInbound(tag, port, credentials) {
	if (!diagnosticPort(port) || !diagnosticCredentials(credentials)) die("invalid_diagnostic_inbound");
	return { tag: tag, listen: "127.0.0.1", port: port, protocol: "socks",
		settings: { auth: "password", accounts: [{ user: credentials.user, pass: credentials.pass }],
			udp: true, ip: "127.0.0.1" } };
}

export { buildDiagnosticInbound, buildInbound, buildSocksTestInbound, buildDnsInbound, DNS_INBOUND_PORT };
