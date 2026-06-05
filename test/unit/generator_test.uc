import { test, assert, assertEq, assertThrows, run } from "../harness.uc";
import { parse } from "../../src/parser/subscription.uc";
import { generate, buildRouting, buildStreamSettings } from "../../src/generator/xray.uc";
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

exit(run());
