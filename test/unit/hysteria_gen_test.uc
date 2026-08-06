// hysteria2: конфиг клиента, socks-аутбаунд xray и подготовка процесса в rpcd.
import { test, assert, assertEq, run } from "../harness.uc";
import { parse } from "../../src/parser/subscription.uc";
import { generate, generateProbe } from "../../src/generator/xray.uc";
import { hysteriaConfig, hysteriaOutbound, isHysteria, serverAddress } from "../../src/generator/hysteria.uc";
import { prepareHysteria } from "../../src/rpcd/hysteria.uc";

const HY = parse("hysteria2://p%40ss@h.example.com:8443/?sni=cdn.example&insecure=1" +
	"&obfs=salamander&obfs-password=zz&pinSHA256=AA:BB#HY").servers[0];
const HY_PLAIN = parse("hy2://secret@vpn.example.net").servers[0];
const VLESS = parse("vless://11111111-2222-3333-4444-555555555555@v.example:443?pbk=K#V").servers[0];

function mockCtx(state) {
	return {
		hysteriaInstalled: function() { return state.installed; },
		applyHysteria: function(j) { state.written = j; return state.applyErr; },
	};
}

test("isHysteria distinguishes protocols", function() {
	assert(isHysteria(HY), "hy2 server");
	assert(!isHysteria(VLESS), "vless server");
	assert(!isHysteria(null), "null is not hysteria");
});

test("client config carries auth, tls and obfs", function() {
	let c = hysteriaConfig(HY);
	assertEq(c.server, "h.example.com:8443");
	assertEq(c.auth, "p@ss");
	assertEq(c.tls, { sni: "cdn.example", insecure: true, pinSHA256: "AA:BB" });
	assertEq(c.obfs, { type: "salamander", salamander: { password: "zz" } });
	assertEq(c.socks5, { listen: "127.0.0.1:10810" });
	assert(c.lazy === true, "lazy start");
});

test("client config without optional fields", function() {
	let c = hysteriaConfig(HY_PLAIN);
	assertEq(c.server, "vpn.example.net:443");
	assertEq(c.tls, { sni: "vpn.example.net", insecure: false });
	assert(c.obfs == null, "no obfs section");
	assert(!exists(c, "bandwidth"), "bandwidth left to BBR");
});

// Порт-хоппинг живёт в адресе сервера, отдельного поля у hysteria нет.
test("mport replaces the plain port in the server address", function() {
	let s = parse("hy2://a@h.example:443?mport=10000-20000#H").servers[0];
	assertEq(serverAddress(s), "h.example:10000-20000");
});

// Без скобок "2001:db8::1:443" клиент читает как адрес без порта и уезжает мимо сервера.
test("IPv6 literal is bracketed in the server address", function() {
	let s = parse("hy2://a@[2001:db8::1]:8443#v6").servers[0];
	assertEq(serverAddress(s), "[2001:db8::1]:8443");
	assertEq(serverAddress({ address: "2001:db8::1", port: 443, mport: "10000-20000" }),
		"[2001:db8::1]:10000-20000");
});

test("probe config uses its own socks port", function() {
	let c = hysteriaConfig(HY, { socksPort: 10811 });
	assertEq(c.socks5, { listen: "127.0.0.1:10811" });
});

// Смысл всей связки: маршрутизация xray не меняется, меняется только куда смотрит "proxy".
test("xray outbound becomes socks into the local hysteria", function() {
	let out = generate({ global: { tproxy_port: 12345, routing_mode: "bypass-local", local_region: "ru" }, server: HY });
	assertEq(out.outbounds[0], {
		tag: "proxy", protocol: "socks",
		settings: { servers: [{ address: "127.0.0.1", port: 10810 }] },
	});
	assertEq(out.outbounds[1].tag, "direct");
	assertEq(out.routing.rules[0].ip, ["geoip:private", "geoip:ru"]);
	assertEq(out.routing.rules[2].outboundTag, "proxy");
});

test("vless outbound is untouched by the hysteria branch", function() {
	let out = generate({ global: { tproxy_port: 12345 }, server: VLESS });
	assertEq(out.outbounds[0].protocol, "vless");
});

test("probe wires xray to the ephemeral hysteria socks", function() {
	let p = generateProbe({ global: {}, dns: {}, server: HY, hysteria_socks_port: 10811 });
	assertEq(p.outbounds[0].settings.servers[0].port, 10811);
	assertEq(hysteriaOutbound({}).settings.servers[0].port, 10810);
});

test("prepareHysteria writes the config for a hysteria server", function() {
	let state = { installed: true };
	assert(prepareHysteria(mockCtx(state), HY) == null, "no error");
	let c = json(state.written);
	assertEq(c.auth, "p@ss");
});

// Иначе после переключения на vless остался бы висеть клиент, долбящийся в старый сервер.
test("prepareHysteria removes the config for a non-hysteria server", function() {
	let state = { installed: true, written: "stale" };
	assert(prepareHysteria(mockCtx(state), VLESS) == null, "no error");
	assert(state.written == null, "config removed");
});

// Молчаливый уход в vless-путь дал бы xray с аутбаундом в пустой порт при живом kill-switch —
// снаружи это «интернет пропал», а не «нет клиента».
test("prepareHysteria refuses when the binary is missing", function() {
	let state = { installed: false };
	let err = prepareHysteria(mockCtx(state), HY);
	assert(err != null, "error returned");
	assert(state.written == null, "nothing written");
});

test("prepareHysteria on a runtime without hysteria support", function() {
	assert(prepareHysteria({}, VLESS) == null, "vless still works");
	assert(prepareHysteria({}, HY) != null, "hy2 reports the missing support");
});

exit(run());
