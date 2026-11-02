import { test, assertEq, assert, run } from "../harness.uc";
import { parseUri } from "../../src/lib/uri.uc";
import { normalizeUri } from "../../src/parser/subscription.uc";
import { reviveServer, flattenServer } from "../../src/lib/servermap.uc";
import { serverToUri } from "../../src/lib/serveruri.uc";
import { serverLink } from "../../src/rpcd/uri.uc";

const PBK = "jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0";
const UUID = "11111111-2222-3333-4444-555555555555";

const LINKS = {
	reality_tcp: "vless://" + UUID + "@ru.example:443?security=reality&pbk=" + PBK +
		"&sid=a1b2&flow=xtls-rprx-vision&sni=www.example&fp=firefox#%F0%9F%9A%80%20RU%20speed",
	reality_xhttp: "vless://" + UUID + "@203.0.113.9:8443?security=reality&pbk=" + PBK +
		"&sid=&spx=%2Fstart%3Fq%3D1&type=xhttp&path=/x%20y&host=cdn.example&mode=packet-up#nl%23bypass",
	tls_ws: "vless://panel-user-42@ws.example:443?security=tls&type=ws&path=/ws%3Fed%3D2048" +
		"&host=front.example&alpn=h2,http/1.1&sni=front.example#ws%20none",
	tls_grpc: "vless://" + UUID + "@[2001:db8::1]:443?security=tls&type=grpc&serviceName=svc%2Bname#v6",
	httpupgrade: "vless://" + UUID + "@hu.example:80?security=none&type=httpupgrade&path=/up#plain",
	hy2_obfs: "hy2://p%40ss%2Fw%3Ard%2B%25@203.0.113.7:443/?sni=www.example&insecure=1" +
		"&obfs=salamander&obfs-password=s4l%26m&pinSHA256=AB:CD:EF&mport=20000-30000#vdska-hy2",
	hy2_plain: "hysteria2://pw@hy.example:8443/?sni=hy.example",
};

function normalize(link) {
	let r = normalizeUri(parseUri(link), link);
	assert(r.error == null, "fixture parses: " + r.error);
	return r.server;
}

function asUci(server) {
	let flat = flattenServer(server);
	let out = {};
	for (let k in flat)
		out[k] = "" + flat[k];
	return out;
}

function stored(server, name) {
	let s = reviveServer(asUci(server));
	s[".name"] = name;
	return s;
}

for (let name in keys(LINKS)) {
	let link = LINKS[name];
	test("round-trip " + name, function() {
		let before = normalize(link);
		let after = normalize(serverToUri(stored(before, "cfg01")));
		assertEq(asUci(after), asUci(before));
	});
}

test("password keeps reserved characters", function() {
	assertEq(normalize(serverToUri(stored(normalize(LINKS.hy2_obfs), "x"))).password, "p@ss/w:rd+%");
});

test("tag with spaces, hash and emoji survives", function() {
	assertEq(normalize(serverToUri(stored(normalize(LINKS.reality_tcp), "x"))).tag, "🚀 RU speed");
	assertEq(normalize(serverToUri(stored(normalize(LINKS.reality_xhttp), "x"))).tag, "nl#bypass");
});

function ctx(servers) {
	return { getServers: function() { return servers; } };
}

function manual(link, name) {
	let s = stored(normalize(link), name);
	s.source = "manual";
	return s;
}

test("server_link returns the link of a manual section", function() {
	let r = serverLink(ctx([manual(LINKS.tls_ws, "cfg02"), manual(LINKS.hy2_obfs, "cfg03")]), { section: "cfg03" });
	assertEq(r.ok, true);
	assertEq(normalize(r.link).password, "p@ss/w:rd+%");
});

test("server_link refuses subscription servers", function() {
	assertEq(serverLink(ctx([stored(normalize(LINKS.tls_ws), "cfg02")]), { section: "cfg02" }).error, "not_manual");
});

test("server_link reports a missing section", function() {
	let servers = [manual(LINKS.tls_ws, "cfg02")];
	assertEq(serverLink(ctx(servers), { section: "cfg09" }).error, "not_found");
	assertEq(serverLink(ctx(servers), { section: "" }).error, "not_found");
	assertEq(serverLink(ctx(servers), null).error, "not_found");
});

exit(run());
