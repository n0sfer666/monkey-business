import { test, assert, assertEq, run } from "../harness.uc";
import { parse, detectFormat, decodeBase64Maybe } from "../../src/parser/subscription.uc";
import { readfile } from "fs";

const URILIST = readfile("test/fixtures/sub_urilist.txt");
const BASE64 = readfile("test/fixtures/sub_base64.txt");

const SERVER_A = {
	tag: "Server A",
	protocol: "vless",
	address: "a.example.com",
	port: 443,
	uuid: "11111111-2222-3333-4444-555555555555",
	encryption: "none",
	flow: "xtls-rprx-vision",
	security: "reality",
	sni: "www.microsoft.com",
	fingerprint: "chrome",
	alpn: [],
	reality: { publicKey: "PUBKEYA", shortId: "ab12", spiderX: "/" },
	transport: { type: "xhttp", path: "/xhttp", host: "", mode: "auto", serviceName: "" },
	source: "subscription",
};

test("detectFormat classifies inputs", function() {
	assertEq(detectFormat(URILIST), "uri-list");
	assertEq(detectFormat(BASE64), "base64");
	assertEq(detectFormat('{"x":1}'), "json");
	assertEq(detectFormat("proxies:\n  - name: a"), "clash");
	assertEq(detectFormat("just text"), "unknown");
	assertEq(detectFormat(""), "unknown");
});

test("parse uri-list yields normalized servers", function() {
	let r = parse(URILIST);
	assertEq(r.format, "uri-list");
	assertEq(length(r.servers), 2);
	assertEq(r.servers[0], SERVER_A);
	assertEq(r.servers[1].address, "b.example.com");
	assertEq(r.servers[1].security, "tls");
	assertEq(r.servers[1].transport.type, "ws");
	assertEq(r.servers[1].reality, null);
	assertEq(r.servers[1].tag, "Server B");
	assert(length(r.errors) >= 1, "ss line reported as error");
});

test("parse base64 decodes then parses", function() {
	let r = parse(BASE64);
	assertEq(r.format, "base64");
	assertEq(length(r.servers), 2);
	assertEq(r.servers[0], SERVER_A);
});

test("parse empty input", function() {
	let r = parse("");
	assertEq(r.format, "unknown");
	assertEq(r.servers, []);
	assertEq(r.errors, ["empty input"]);
});

test("parse garbage input", function() {
	let r = parse("this is not a subscription");
	assertEq(r.format, "unknown");
	assertEq(length(r.servers), 0);
});

test("parse reports missing uuid and bad port", function() {
	let r = parse("vless://@host.tld:443#x\nvless://uuid@host.tld:0#y");
	assertEq(length(r.servers), 0);
	assertEq(length(r.errors), 2);
});

test("parse skips comments and blanks", function() {
	let r = parse("# only a comment\n\n   \n");
	assertEq(r.format, "unknown");
	assertEq(length(r.servers), 0);
});

test("parse normalizes hysteria2 uri into the shared contract", function() {
	let r = parse("hysteria2://p%40ss@h.example.com:8443/?sni=cdn.example&insecure=1" +
		"&obfs=salamander&obfs-password=zz&pinSHA256=AA:BB&mport=10000-20000#HY");
	assertEq(length(r.errors), 0);
	let s = r.servers[0];
	assertEq(s.protocol, "hysteria2");
	assertEq(s.tag, "HY");
	assertEq(s.address, "h.example.com");
	assertEq(s.port, 8443);
	// userinfo декодируется: панели пишут туда пароли со спецсимволами
	assertEq(s.password, "p@ss");
	assertEq(s.sni, "cdn.example");
	assertEq(s.insecure, "1");
	assertEq(s.pin_sha256, "AA:BB");
	assertEq(s.mport, "10000-20000");
	assertEq(s.obfs, { type: "salamander", password: "zz" });
	assertEq(s.uuid, "");
	assertEq(s.transport, { type: "quic", path: "", host: "", mode: "", serviceName: "" });
});

test("hy2 alias, default port and sni fallback", function() {
	let r = parse("hy2://secret@vpn.example.net");
	let s = r.servers[0];
	assertEq(s.protocol, "hysteria2");
	assertEq(s.port, 443);
	assertEq(s.sni, "vpn.example.net");
	assertEq(s.tag, "vpn.example.net:443");
	assert(s.obfs == null, "no obfs param -> null");
	assertEq(s.insecure, "0");
});

test("hysteria2 rejects an invalid port", function() {
	let r = parse("hy2://secret@vpn.example.net:0#bad");
	assertEq(length(r.servers), 0);
	assertEq(length(r.errors), 1);
});

// Диапазон в позиции порта parseUri оставляет частью host: молчаливая подстановка 443 давала бы
// сервер "h.example:10000-20000:443", снаружи неотличимый от нерабочего.
test("hysteria2 rejects a port range written into the address", function() {
	let r = parse("hy2://secret@h.example:10000-20000#bad");
	assertEq(length(r.servers), 0);
	assertEq(length(r.errors), 1);
});

test("hysteria2 keeps a bare IPv6 literal as the address", function() {
	let s = parse("hy2://secret@2001:db8::1#v6").servers[0];
	assertEq(s.address, "2001:db8::1");
	assertEq(s.port, 443);
});

// Протокол — свойство сервера: оба вида живут в ОДНОМ списке, порядок = приоритет, и failover
// перебирает их сквозь протоколы.
test("mixed subscription keeps both protocols in one ordered list", function() {
	let r = parse("hy2://a@h1.example:443#one\nvless://11111111-2222-3333-4444-555555555555@h2.example:443?pbk=K#two");
	assertEq(length(r.errors), 0);
	assertEq(length(r.servers), 2);
	assertEq(r.servers[0].protocol, "hysteria2");
	assertEq(r.servers[1].protocol, "vless");
});

test("decodeBase64Maybe rejects non-base64", function() {
	assert(decodeBase64Maybe("@@@not base64@@@") == null, "garbage -> null");
});

exit(run());
