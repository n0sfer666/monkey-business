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

test("decodeBase64Maybe rejects non-base64", function() {
	assert(decodeBase64Maybe("@@@not base64@@@") == null, "garbage -> null");
});

exit(run());
