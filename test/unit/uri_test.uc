import { test, assertEq, assert, run } from "../harness.uc";
import { urldecode, parseQuery, parseUri } from "../../src/lib/uri.uc";

test("urldecode percent sequences", function() {
	assertEq(urldecode("hello%20world"), "hello world");
	assertEq(urldecode("%2Ffoo%2Fbar"), "/foo/bar");
	assertEq(urldecode("plain"), "plain");
	assertEq(urldecode("trailing%"), "trailing%");
});

test("parseQuery decodes pairs", function() {
	assertEq(parseQuery("a=1&b=hello%20world&flag"),
		{ a: "1", b: "hello world", flag: "" });
	assertEq(parseQuery(""), {});
	assertEq(parseQuery("x=a+b"), { x: "a b" });
});

test("parseUri vless with query and fragment", function() {
	let u = parseUri("vless://11111111-2222-3333-4444-555555555555@example.com:443?type=xhttp&security=reality&sni=www.microsoft.com&pbk=KEY&sid=ab12&flow=xtls-rprx-vision#My%20Server");
	assertEq(u.scheme, "vless");
	assertEq(u.user, "11111111-2222-3333-4444-555555555555");
	assertEq(u.host, "example.com");
	assertEq(u.port, 443);
	assertEq(u.query.type, "xhttp");
	assertEq(u.query.security, "reality");
	assertEq(u.query.sni, "www.microsoft.com");
	assertEq(u.fragment, "My Server");
});

test("parseUri ipv6 host", function() {
	let u = parseUri("vless://uuid@[2001:db8::1]:8443?type=tcp#v6");
	assertEq(u.host, "2001:db8::1");
	assertEq(u.port, 8443);
});

test("parseUri ipv6 host without brackets keeps full address", function() {
	let u = parseUri("vless://uuid@2001:db8::1?type=tcp#v6");
	assertEq(u.host, "2001:db8::1");
	assertEq(u.port, null);
});

test("parseUri without port or query", function() {
	let u = parseUri("vless://uuid@host.tld#name");
	assertEq(u.host, "host.tld");
	assertEq(u.port, null);
	assertEq(u.fragment, "name");
});

test("parseUri rejects garbage", function() {
	assert(parseUri("not a uri") == null, "garbage -> null");
	assert(parseUri("") == null, "empty -> null");
	assert(parseUri(123) == null, "non-string -> null");
});

exit(run());
