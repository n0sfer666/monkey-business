import { test, assert, assertEq, run } from "../harness.uc";
import * as hsel from "../../src/rpcd/select.uc";
import { LEGACY_SUB, findSelected, dropOrphans, activeSubId, subAlive, subsOrLegacy } from "../../src/lib/subs.uc";
import { loadServers, storeServers } from "../../src/runtime/uci.uc";
import { NOW, srv, manual, sub, tags, mockCursor } from "../subfixtures.uc";

test("candidates: active subscription and manual first, then reserve by subscription order", function() {
	let servers = [ srv("b1", "2.0.0.1", "b"), manual("m1", "9.0.0.1"), srv("a1", "1.0.0.1", "a"),
		srv("b2", "2.0.0.2", "b"), srv("c1", "3.0.0.1", "c"), srv("a2", "1.0.0.2", "a") ];
	let out = hsel.candidates(servers, [ sub("a"), sub("b"), sub("c") ], "b", NOW);
	assertEq(tags(out), [ "b1", "m1", "b2", "a1", "a2", "c1" ]);
});

test("unknown or empty active_sub falls back to the first subscription", function() {
	let subs = [ sub("a"), sub("b") ];
	assertEq(activeSubId(subs, "gone"), "a");
	assertEq(activeSubId(subs, ""), "a");
	assertEq(activeSubId(subs, null), "a");
	assert(activeSubId([], "a") == null, "без подписок активной нет");
	let out = hsel.candidates([ srv("b1", "2.0.0.1", "b"), srv("a1", "1.0.0.1", "a") ], subs, "gone", NOW);
	assertEq(tags(out), [ "a1", "b1" ]);
});

test("no subscription sections means the legacy subscription still exists", function() {
	let subs = subsOrLegacy([]);
	assertEq(activeSubId(subs, ""), LEGACY_SUB);
	assertEq(tags(dropOrphans([ srv("old", "3.0.0.1", LEGACY_SUB) ], subs)), [ "old" ]);
	assertEq(subsOrLegacy([ sub("a") ]), [ sub("a") ]);
});

test("manually disabled servers are listed but never candidates", function() {
	let off = manual("m1", "9.0.0.1");
	off.disabled = "1";
	let dis = srv("a1", "1.0.0.1", "a");
	dis.disabled = "1";
	let servers = [ off, dis, srv("a2", "1.0.0.2", "a") ];
	assertEq(tags(hsel.grouped(servers, [ sub("a") ], "a")), [ "m1", "a1", "a2" ]);
	assertEq(tags(hsel.candidates(servers, [ sub("a") ], "a", NOW)), [ "a2" ]);
});

test("dead reserve subscriptions are skipped, a dead active one stays", function() {
	let subs = [
		sub("a", { expire: "" + (NOW - 1) }),
		sub("b", { total: "100", used_upload: "60", used_download: "40" }),
		sub("c", { total: "", used_upload: "", expire: "" + (NOW + 3600) }),
	];
	assert(!subAlive(subs[0], NOW), "истёкшая");
	assert(!subAlive(subs[1], NOW), "исчерпанная");
	assert(subAlive(subs[2], NOW), "живая с пустыми полями");
	let servers = [ srv("a1", "1.0.0.1", "a"), srv("b1", "2.0.0.1", "b"), srv("c1", "3.0.0.1", "c") ];
	assertEq(tags(hsel.candidates(servers, subs, "a", NOW)), [ "a1", "c1" ]);
});

test("orphans of a deleted subscription are not listed", function() {
	let servers = [ srv("a1", "1.0.0.1", "a"), srv("g1", "7.0.0.1", "gone"), manual("m1", "9.0.0.1") ];
	assertEq(tags(dropOrphans(servers, [ sub("a") ])), [ "a1", "m1" ]);
	assertEq(tags(hsel.grouped(servers, [ sub("a") ], "a")), [ "a1", "m1" ]);
});

function uciServer(tag, address, sub_) {
	let s = { ".type": "server", tag: tag, protocol: "vless", address: address, port: "443",
		source: "subscription" };
	if (sub_ != null)
		s.sub = sub_;
	return s;
}

test("loadServers drops orphans and the next write does not keep them", function() {
	let cur = mockCursor([ { ".name": "a", ".type": "subscription" }, uciServer("a1", "1.0.0.1", "a"),
		uciServer("g1", "7.0.0.1", "gone") ]);
	let servers = loadServers(cur);
	assertEq(tags(servers), [ "a1" ]);
	storeServers(cur, servers);
	assertEq(tags(filter(cur.all(), function(s) { return s[".type"] == "server"; })), [ "a1" ]);
});

test("loadServers keeps legacy servers when no subscription section exists", function() {
	let cur = mockCursor([ uciServer("old", "3.0.0.1", null), uciServer("old2", "3.0.0.2", LEGACY_SUB) ]);
	assertEq(tags(loadServers(cur)), [ "old", "old2" ]);
});

test("a legacy bare tag in the active file finds the manual server first, then the first one", function() {
	let servers = [ srv("x", "1.0.0.1", "a"), srv("x", "2.0.0.1", "b") ];
	assertEq(findSelected(servers, "x").address, "1.0.0.1");
	assertEq(findSelected(servers, "b/x").address, "2.0.0.1");
	assertEq(findSelected([ srv("x", "1.0.0.1", "a"), manual("x", "9.0.0.1") ], "x").address, "9.0.0.1");
	assert(findSelected(servers, "c/x") == null, "чужая идентичность не матчится");
	assert(findSelected(servers, "") == null, "пустой выбор");
	assert(findSelected(servers, null) == null, "нет файла");
});

exit(run());
