import { test, assert, assertEq, assertThrows, run } from "../harness.uc";
import { parse } from "../../src/parser/subscription.uc";
import { generate, buildRouting, buildStreamSettings, buildDns } from "../../src/generator/xray.uc";
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
		{ tproxy_port: 12345, routing_mode: "bypass-local", local_region: "ru", log_level: "warning" },
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
	let r = buildRouting({ routing_mode: "global" });
	assertEq(r.rules[0].ip, ["geoip:private"]);
	assertEq(r.rules[length(r.rules) - 1].outboundTag, "proxy");
});

test("routing mode: gfwlist", function() {
	let r = buildRouting({ routing_mode: "gfwlist", local_region: "ru" });
	assertEq(r.rules[length(r.rules) - 1].outboundTag, "direct");
	assert(r.rules[1].domain[0] == "geosite:geolocation-!ru", "proxy by !region list");
});

test("routing mode: bypass-local default region ru", function() {
	let r = buildRouting({});
	assertEq(r.rules[0].ip, ["geoip:private", "geoip:ru"]);
	assertEq(r.rules[1].domain, ["geosite:private", "geosite:category-ru"]);
});

test("routing region other: drops region geo, private direct, default by mode", function() {
	let r = buildRouting({ local_region: "other", routing_mode: "bypass-local" });
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
		local_region: "other", routing_mode: "bypass-local",
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
	let r = buildRouting({ routing_mode: "bypass-local" });
	assertEq(r.rules[0].outboundTag, "direct");
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
	let r = buildRouting({ routing_mode: "global", custom_direct: "example.com", custom_proxy: "x.com" });
	for (let rule in r.rules)
		assert(!(exists(rule, "domain") && index(rule.domain, "example.com") >= 0), "no custom rule in global");
	assertEq(r.rules[0].ip, ["geoip:private"]);
});

exit(run());
