import { test, assertEq, run } from "../harness.uc";
import { entries, checkEntry, validateRules } from "../../src/lib/rules.uc";

function code(t) {
	let e = checkEntry(t);
	return (e == null) ? null : e.code;
}

test("valid entries pass", function() {
	for (let t in ["example.com", "*.example.com", "a-b.example.co", "xn--p1ai.xn--p1ai", "1.2.3.4",
		"10.0.0.0/8", "0.0.0.0/32", "2001:db8::1", "2001:db8::/32", "::/0", "geosite:netflix",
		"GEOSITE:category-ru", "geoip:ru", "geosite:geolocation-!cn", "geosite:google@cn", "*.ru", "*.xn--p1ai",
		"a_b.example.com", "::", "::ffff:1.2.3.4", "1:2:3:4:5:6:7:8", "fe80::1/64", "full:example.com",
		"domain:example.com", "keyword:google", "regexp:^ya\\.ru$", "Full:x.org"])
		assertEq(checkEntry(t), null, t);
});

test("each invalid entry maps to its code and arg", function() {
	assertEq(checkEntry("a b.com"), { code: "space", arg: "" });
	assertEq(checkEntry("https://site.com/x"), { code: "scheme", arg: "site.com" });
	assertEq(checkEntry("geosite:"), { code: "geo_empty", arg: "geosite" });
	assertEq(checkEntry("GEOIP:"), { code: "geo_empty", arg: "geoip" });
	assertEq(checkEntry("geoip:r$u"), { code: "geo_name", arg: "geoip" });
	assertEq(checkEntry("10.0.0.0/8/9"), { code: "slashes", arg: "" });
	assertEq(checkEntry("1.2.3.256"), { code: "ip4", arg: "" });
	assertEq(checkEntry("1.2.3"), { code: "ip4", arg: "" });
	assertEq(checkEntry("10.0.0.0/33"), { code: "prefix", arg: "32" });
	assertEq(checkEntry("2001:db8::/129"), { code: "prefix", arg: "128" });
	assertEq(checkEntry("::ffff:1.2.3.0/33"), { code: "prefix", arg: "32" });
	assertEq(checkEntry("::FFFF:1.2.3.0/120"), { code: "prefix", arg: "32" });
	assertEq(checkEntry("::ffff:1.2.3.0/24"), null);
	for (let t in ["0:0:0:0:0:ffff:1.2.3.4", "::0:ffff:1.2.3.4", "0::ffff:1.2.3.4/24", "::ffff:102:304"])
		assertEq(checkEntry(t), { code: "mapped", arg: "::ffff:1.2.3.4" }, t);
	assertEq(checkEntry("2001:zz::1"), { code: "ip6", arg: "" });
	assertEq(checkEntry("1::2::3"), { code: "ip6", arg: "" });
	for (let t in [":", "1:2:3", "12345::1", "1:2:3:4:5:6:7:8:9", "1:2:3:4::5:6:7:8", "::ffff:1.2.3.256"])
		assertEq(checkEntry(t), { code: "ip6", arg: "" }, t);
	assertEq(checkEntry("010.0.0.1"), { code: "ip4", arg: "" });
	assertEq(checkEntry("example.com:443"), { code: "port", arg: "example.com" });
	assertEq(checkEntry("1.2.3.4:80"), { code: "port", arg: "1.2.3.4" });
	assertEq(checkEntry("keyword:"), { code: "matcher_empty", arg: "keyword" });
	assertEq(checkEntry("site.com/path"), { code: "path", arg: "site.com" });
	assertEq(checkEntry("a*.com"), { code: "wildcard", arg: "" });
	assertEq(checkEntry("*."), { code: "incomplete", arg: "" });
	assertEq(checkEntry("a..com"), { code: "incomplete", arg: "" });
	assertEq(checkEntry("localhost"), { code: "not_full", arg: "localhost" });
	assertEq(checkEntry("*.c0rp"), { code: "not_full", arg: "c0rp" });
	assertEq(checkEntry("-a.com"), { code: "chars", arg: "" });
	assertEq(checkEntry("a$b.com"), { code: "chars", arg: "" });
	assertEq(checkEntry("site.c0m"), { code: "tld", arg: "" });
});

test("unknown prefixes are not taken for xray matchers", function() {
	assertEq(code("ext:file.dat:tag"), "ip6");
	assertEq(code("foo:bar"), "ip6");
});

test("entries skip blanks and comments, split commas, keep line numbers", function() {
	assertEq(entries("a.com\n\n# note\n b.com , c.com ,\n"), [
		{ line: 1, value: "a.com" },
		{ line: 4, value: "b.com" },
		{ line: 4, value: "c.com" },
	]);
	assertEq(entries(null), []);
	assertEq(entries(""), []);
});

test("validateRules reports one error per line, direct first", function() {
	let r = validateRules("ok.com\nbad one, also bad\n#x\nlocalhost", "geoip:\nfine.org");
	assertEq(r, [
		{ list: "direct", line: 2, code: "space", arg: "" },
		{ list: "direct", line: 4, code: "not_full", arg: "localhost" },
		{ list: "proxy", line: 1, code: "geo_empty", arg: "geoip" },
	]);
	assertEq(validateRules("", null), []);
});

exit(run());
