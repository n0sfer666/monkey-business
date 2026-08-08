import { test, assert, assertEq, assertThrows, run } from "../harness.uc";
import { parse } from "../../src/parser/subscription.uc";
import { generate } from "../../src/generator/xray.uc";
import { buildRouting } from "../../src/generator/routing.uc";
import { buildStreamSettings } from "../../src/generator/outbounds.uc";
import { buildDns } from "../../src/generator/dns.uc";
import { readfile } from "fs";

const SERVERS = parse(readfile("test/fixtures/sub_urilist.txt")).servers;
const SERVER_A = SERVERS[0];
const SERVER_B = SERVERS[1];

function cfg(global, server) {
	return { global: global, server: server };
}

test("bypass-ru matches golden snapshot", function() {
	let golden = json(readfile("test/fixtures/xray_bypass_ru.json"));
	let out = generate(cfg(
		{ tproxy_port: 12345, routing_mode: "bypass-local", local_region: "ru", log_level: "warning",
		  ipv6_block: "0" },
		SERVER_A));
	assertEq(out, golden);
});

test("inbound is tproxy dokodemo-door", function() {
	let out = generate(cfg({ tproxy_port: 99 }, SERVER_A));
	assertEq(out.inbounds[0].protocol, "dokodemo-door");
	assertEq(out.inbounds[0].port, 99);
	assertEq(out.inbounds[0].streamSettings.sockopt.tproxy, "tproxy");
});

test("reality + xhttp stream settings", function() {
	let ss = buildStreamSettings(SERVER_A);
	assertEq(ss.network, "xhttp");
	assertEq(ss.security, "reality");
	assertEq(ss.realitySettings.publicKey, "PUBKEYA");
	assertEq(ss.xhttpSettings.mode, "auto");
});

test("ws + tls stream settings (server B)", function() {
	let ss = buildStreamSettings(SERVER_B);
	assertEq(ss.network, "ws");
	assertEq(ss.security, "tls");
	assertEq(ss.wsSettings.headers.Host, "b.example.com");
	assert(ss.realitySettings == null, "no reality for tls");
});

test("flow omitted when empty", function() {
	let out = generate(cfg({}, SERVER_B));
	let user = out.outbounds[0].settings.vnext[0].users[0];
	assert(!exists(user, "flow"), "no flow key when empty");
});

test("routing mode: global", function() {
	let r = buildRouting({ routing_mode: "global", ipv6_block: "0" });
	assertEq(r.rules[0].ip, ["geoip:private"]);
	assertEq(r.rules[length(r.rules) - 1].outboundTag, "proxy");
});

test("routing mode: gfwlist", function() {
	let r = buildRouting({ routing_mode: "gfwlist", local_region: "ru", ipv6_block: "0" });
	assertEq(r.rules[length(r.rules) - 1].outboundTag, "direct");
	assert(r.rules[1].domain[0] == "geosite:geolocation-!ru", "proxy by !region list");
});

test("routing mode: bypass-local default region ru", function() {
	let r = buildRouting({ ipv6_block: "0" });
	assertEq(r.rules[0].ip, ["geoip:private", "geoip:ru"]);
	assertEq(r.rules[1].domain, ["geosite:private", "geosite:category-ru"]);
});

// Обещание дашборда: не выбрал bypass-local — geoip:<region>/geosite:<region> в direct не уходят
// вовсе (и ядерный обход выключается вместе с ними, см. directBypass в lib/bypass.uc).
test("region geo goes direct only in bypass-local", function() {
	for (let mode in ["global", "gfwlist"]) {
		let r = buildRouting({ routing_mode: mode, local_region: "ru" });
		for (let rule in r.rules) {
			if (rule.outboundTag != "direct")
				continue;
			for (let v in (rule.ip || []))
				assert(v != "geoip:ru", "no geoip:ru direct rule in " + mode);
			for (let v in (rule.domain || []))
				assert(v != "geosite:category-ru", "no geosite:category-ru direct rule in " + mode);
		}
	}
});

test("routing region other: drops region geo, private direct, default by mode", function() {
	let r = buildRouting({ local_region: "other", routing_mode: "bypass-local", ipv6_block: "0" });
	assertEq(r.rules[0].ip, ["geoip:private"]);
	assertEq(r.rules[0].outboundTag, "direct");
	assertEq(r.rules[1].domain, ["geosite:private"]);
	assertEq(r.rules[1].outboundTag, "direct");
	assertEq(r.rules[length(r.rules) - 1].network, "tcp,udp");
	assertEq(r.rules[length(r.rules) - 1].outboundTag, "proxy");
});

test("routing region other: ipv6 block kept first", function() {
	let r = buildRouting({ local_region: "other", routing_mode: "bypass-local", ipv6_block: "1" });
	assertEq(r.rules[0].ip, ["::/0"]);
	assertEq(r.rules[0].outboundTag, "block");
	assertEq(r.rules[1].ip, ["geoip:private"]);
	assertEq(r.rules[length(r.rules) - 1].outboundTag, "proxy");
});

test("routing region other: custom lists drive split, no region geo category", function() {
	let r = buildRouting({
		local_region: "other", routing_mode: "bypass-local", ipv6_block: "0",
		custom_direct: "a.com", custom_proxy: "b.com",
	});
	assertEq(r.rules[0].domain, ["a.com"]);
	assertEq(r.rules[0].outboundTag, "direct");
	assertEq(r.rules[1].domain, ["b.com"]);
	assertEq(r.rules[1].outboundTag, "proxy");
	for (let rule in r.rules) {
		if (exists(rule, "ip"))
			for (let v in rule.ip)
				assert(index(v, "geoip:other") < 0, "no geoip:other category");
		if (exists(rule, "domain"))
			for (let v in rule.domain)
				assert(index(v, ":other") < 0, "no geosite:other category");
	}
});

test("routing region other + gfwlist: no geolocation-!other, default direct", function() {
	let r = buildRouting({ local_region: "other", routing_mode: "gfwlist", custom_proxy: "x.com" });
	for (let rule in r.rules)
		if (exists(rule, "domain"))
			for (let v in rule.domain)
				assert(index(v, "geolocation-!") < 0, "no geolocation-! list for other");
	assertEq(r.rules[length(r.rules) - 1].outboundTag, "direct");
});

test("dns region other: split direct private only, no geosite:other", function() {
	let d = buildDns({ mode: "split", direct_dns: "1.1.1.1", doh_url: "https://1.1.1.1/dns-query" }, "other", "1");
	assertEq(d.servers[0].domains, ["geosite:private"]);
	assertEq(d.servers[1], "https://1.1.1.1/dns-query");
	assertEq(d.queryStrategy, "UseIPv4");
});

test("generate dies without server", function() {
	assertThrows(function() { generate({ global: {} }); });
});

test("transparent dns adds dns-in inbound, dns-out outbound, first routing rule", function() {
	let out = generate({
		global: { tproxy_port: 12345, routing_mode: "bypass-local", local_region: "ru" },
		server: SERVER_A,
		dns: { mode: "split", direct_dns: "77.88.8.8", doh_url: "https://1.1.1.1/dns-query" },
		dns_transparent: true,
	});
	let dnsIn = null;
	for (let ib in out.inbounds) if (ib.tag == "dns-in") dnsIn = ib;
	assert(dnsIn != null, "dns-in inbound present");
	assertEq(dnsIn.protocol, "dokodemo-door");
	assertEq(dnsIn.port, 5300);
	let dnsOut = null;
	for (let ob in out.outbounds) if (ob.tag == "dns-out") dnsOut = ob;
	assert(dnsOut != null, "dns-out outbound present");
	assertEq(dnsOut.protocol, "dns");
	assertEq(out.routing.rules[0].inboundTag, ["dns-in"]);
	assertEq(out.routing.rules[0].outboundTag, "dns-out");
});

test("no transparent dns by default (golden unaffected)", function() {
	let out = generate(cfg({ tproxy_port: 12345, routing_mode: "bypass-local", local_region: "ru" }, SERVER_A));
	for (let ib in out.inbounds) assert(ib.tag != "dns-in", "no dns-in without flag");
	for (let ob in out.outbounds) assert(ob.tag != "dns-out", "no dns-out without flag");
});

const STAGE4_CFG = {
	global: { tproxy_port: 12345, routing_mode: "bypass-local", local_region: "ru", log_level: "warning", ipv6_block: "1" },
	server: SERVER_A,
	anti_dpi: { xhttp_padding: "1" },
	dns: { mode: "split", direct_dns: "223.5.5.5", doh_url: "https://1.1.1.1/dns-query" },
};

test("stage-4 config matches golden snapshot", function() {
	let golden = json(readfile("test/fixtures/xray_stage4.json"));
	assertEq(generate(STAGE4_CFG), golden);
});

test("ipv6 block adds blackhole rule first", function() {
	let r = buildRouting({ ipv6_block: "1", routing_mode: "bypass-local" });
	assertEq(r.rules[0].ip, ["::/0"]);
	assertEq(r.rules[0].outboundTag, "block");
});

test("no ipv6 rule when ipv6_block off", function() {
	let r = buildRouting({ routing_mode: "bypass-local", ipv6_block: "0" });
	assertEq(r.rules[0].outboundTag, "direct");
});

// Опцию из UCI удаляет сама форма LuCI, когда значение совпало с default; трактовать это как
// «выключено» значило бы снимать блок ::/0 после обычного Save & Apply.
test("ipv6 block stays on when the option is missing", function() {
	let r = buildRouting({ routing_mode: "bypass-local" });
	assertEq(r.rules[0].ip, ["::/0"]);
	assertEq(r.rules[0].outboundTag, "block");
	assertEq(buildDns({}, "ru", null).queryStrategy, "UseIPv4");
});

test("routing pins direct_dns resolver to direct (bootstrap)", function() {
	let r = buildRouting({ routing_mode: "bypass-local", local_region: "ru", ipv6_block: "1" }, "77.88.8.8");
	// direct_dns-правило идёт ПЕРЕД ipv6-block и geo -> первым
	assertEq(r.rules[0].ip, ["77.88.8.8"]);
	assertEq(r.rules[0].outboundTag, "direct");
});

test("routing without direct_dns arg unchanged (backward compat)", function() {
	let r = buildRouting({ routing_mode: "bypass-local", local_region: "ru", ipv6_block: "0" });
	assertEq(r.rules[0].ip, ["geoip:private", "geoip:ru"]);
});

test("generate pins direct_dns from dns config to direct", function() {
	let out = generate({
		global: { routing_mode: "bypass-local", local_region: "ru" },
		server: SERVER_A,
		dns: { direct_dns: "77.88.8.8", doh_url: "https://1.1.1.1/dns-query" },
	});
	let pinned = false;
	for (let rule in out.routing.rules)
		if (exists(rule, "ip") && index(rule.ip, "77.88.8.8") >= 0 && rule.outboundTag == "direct")
			pinned = true;
	assert(pinned, "direct_dns pinned to direct outbound");
});

test("custom direct precedes ipv6 block (whitelist overrides ::/0)", function() {
	let r = buildRouting({
		routing_mode: "bypass-local", local_region: "ru", ipv6_block: "1",
		custom_direct: "2001:db8::1\nexample.com",
	});
	let blockIdx = null, directIp6Idx = null, directDomIdx = null, i = 0;
	for (let rule in r.rules) {
		if (rule.outboundTag == "block" && exists(rule, "ip") && index(rule.ip, "::/0") >= 0) blockIdx = i;
		if (rule.outboundTag == "direct" && exists(rule, "ip") && index(rule.ip, "2001:db8::1") >= 0) directIp6Idx = i;
		if (rule.outboundTag == "direct" && exists(rule, "domain") && index(rule.domain, "example.com") >= 0) directDomIdx = i;
		i++;
	}
	assert(directIp6Idx != null && blockIdx != null, "both rules present");
	assert(directIp6Idx < blockIdx, "custom direct ipv6 before ::/0 block");
	assert(directDomIdx < blockIdx, "custom direct domain before ::/0 block");
});

test("dns split: direct for region, doh fallback", function() {
	let d = buildDns({ direct_dns: "223.5.5.5", doh_url: "https://1.1.1.1/dns-query" }, "ru", "1");
	assertEq(d.servers[0].address, "223.5.5.5");
	assertEq(d.servers[0].domains, ["geosite:private", "geosite:category-ru"]);
	assertEq(d.servers[1], "https://1.1.1.1/dns-query");
	assertEq(d.queryStrategy, "UseIPv4");
});

test("dns queryStrategy UseIP when ipv6 allowed", function() {
	let d = buildDns({}, "ru", "0");
	assertEq(d.queryStrategy, "UseIP");
});

test("dns mode doh: single DoH server, no direct region resolve", function() {
	let d = buildDns({ mode: "doh", direct_dns: "223.5.5.5", doh_url: "https://1.1.1.1/dns-query" }, "ru", "1");
	assertEq(d.servers, ["https://1.1.1.1/dns-query"]);
	assertEq(d.queryStrategy, "UseIPv4");
});

test("dns resolves VPN server domain directly (bootstrap, split)", function() {
	let d = buildDns({ direct_dns: "77.88.8.8", doh_url: "https://1.1.1.1/dns-query" }, "ru", "1",
		{ address: "tds.vpnon-connect.tech" });
	// домен сервера — первым в direct-резолвере, чтобы туннель поднялся без резолва через себя
	assertEq(d.servers[0].address, "77.88.8.8");
	assertEq(d.servers[0].domains[0], "full:tds.vpnon-connect.tech");
	assert(index(d.servers[0].domains, "geosite:category-ru") >= 0, "region resolve kept");
});

test("dns bootstrap also in doh mode", function() {
	let d = buildDns({ mode: "doh", direct_dns: "77.88.8.8", doh_url: "https://1.1.1.1/dns-query" }, "ru", "1",
		{ address: "tds.vpnon-connect.tech" });
	assertEq(d.servers[0].domains, ["full:tds.vpnon-connect.tech"]);
	assertEq(d.servers[0].address, "77.88.8.8");
	assertEq(d.servers[1], "https://1.1.1.1/dns-query");
});

test("dns no bootstrap entry for IP-address server", function() {
	let d = buildDns({ direct_dns: "77.88.8.8", doh_url: "https://1.1.1.1/dns-query" }, "ru", "1",
		{ address: "203.0.113.5" });
	assertEq(d.servers[0].domains, ["geosite:private", "geosite:category-ru"]);
});

test("xhttp padding omitted by default", function() {
	let out = generate(cfg({ tproxy_port: 1 }, SERVER_A));
	assert(!exists(out.outbounds[0].streamSettings.xhttpSettings, "xPaddingBytes"), "no padding by default");
});

test("custom direct/proxy lists become routing rules in split mode", function() {
	let r = buildRouting({
		routing_mode: "bypass-local", local_region: "ru",
		custom_direct: "example.com\n1.2.3.0/24\ngeosite:netflix",
		custom_proxy: "geoip:us\nblocked.example",
	});
	// порядок: custom direct(domains), custom direct(ips), custom proxy(domains), custom proxy(ips), затем режим
	assertEq(r.rules[0].domain, ["example.com", "geosite:netflix"]);
	assertEq(r.rules[0].outboundTag, "direct");
	assertEq(r.rules[1].ip, ["1.2.3.0/24"]);
	assertEq(r.rules[1].outboundTag, "direct");
	assertEq(r.rules[2].domain, ["blocked.example"]);
	assertEq(r.rules[2].outboundTag, "proxy");
	assertEq(r.rules[3].ip, ["geoip:us"]);
	assertEq(r.rules[3].outboundTag, "proxy");
});

test("wildcard *.domain becomes xray domain: rule", function() {
	let r = buildRouting({
		routing_mode: "bypass-local", local_region: "ru",
		custom_direct: "*.frontier.com\nplain.com",
		custom_proxy: "*.example.org",
	});
	assertEq(r.rules[0].domain, ["domain:frontier.com", "plain.com"]);
	assertEq(r.rules[0].outboundTag, "direct");
	assertEq(r.rules[1].domain, ["domain:example.org"]);
	assertEq(r.rules[1].outboundTag, "proxy");
});

test("degenerate '*.' is not converted to empty domain: rule", function() {
	let r = buildRouting({
		routing_mode: "bypass-local", local_region: "ru",
		custom_direct: "*.\nkeep.com",
	});
	assertEq(r.rules[0].domain, ["*.", "keep.com"]);
});

test("test_socks adds localhost socks inbound", function() {
	let out = generate({ global: { tproxy_port: 12345 }, server: SERVER_A, test_socks: true });
	assertEq(length(out.inbounds), 2);
	assertEq(out.inbounds[1].tag, "socks-test");
	assertEq(out.inbounds[1].listen, "127.0.0.1");
	assertEq(out.inbounds[1].port, 10808);
	assertEq(out.inbounds[1].protocol, "socks");
});

test("no socks inbound by default", function() {
	let out = generate(cfg({ tproxy_port: 1 }, SERVER_A));
	assertEq(length(out.inbounds), 1);
	assertEq(out.inbounds[0].tag, "tproxy-in");
});

test("custom lists ignored in global mode", function() {
	let r = buildRouting({ routing_mode: "global", custom_direct: "example.com", custom_proxy: "x.com",
		ipv6_block: "0" });
	for (let rule in r.rules)
		assert(!(exists(rule, "domain") && index(rule.domain, "example.com") >= 0), "no custom rule in global");
	assertEq(r.rules[0].ip, ["geoip:private"]);
});

exit(run());
