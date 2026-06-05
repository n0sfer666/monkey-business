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

test("xhttp padding omitted by default", function() {
	let out = generate(cfg({ tproxy_port: 1 }, SERVER_A));
	assert(!exists(out.outbounds[0].streamSettings.xhttpSettings, "xPaddingBytes"), "no padding by default");
});

exit(run());
