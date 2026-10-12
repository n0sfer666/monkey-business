import { test, assert, assertEq, run } from "../harness.uc";
import * as hsub from "../../src/rpcd/subscription.uc";
import { mkState, mockCtx, srv, manual, sub, tags } from "../subfixtures.uc";

const URL = "https://panel/sub/token";
const BODY = "vless://u@4.4.4.4:443?security=none&type=tcp#fresh";

function ids(st) {
	return map(st.subs, function(s) { return s[".name"]; });
}

function state() {
	let st = mkState([ srv("a1", "1.0.0.1", "a") ], [ sub("a", { url: "https://a/sub" }) ], "a");
	st.selected = "a/a1";
	st.hex = [ "0badc0de" ];
	return st;
}

test("subscriptionAdd creates the subscription with its servers and returns its id", function() {
	let st = state();
	st.fetched[URL] = { body: BODY, userinfo: "upload=1; download=2; total=30; expire=40" };
	let r = hsub.subscriptionAdd(mockCtx(st), { name: " Reserve ", url: " " + URL + " " });
	assertEq(r.sub, "sub_0badc0de");
	assertEq(r.added, 1);
	assertEq(ids(st), [ "a", "sub_0badc0de" ]);
	assertEq(st.subs[1].name, "Reserve");
	assertEq(st.subs[1].update_interval, "3600");
	assertEq(tags(st.servers), [ "a1", "fresh" ]);
	assertEq(st.servers[1].sub, "sub_0badc0de");
	assertEq(st.urls.sub_0badc0de, URL);
	assertEq(st.userinfo.sub_0badc0de.total, "30");
	assertEq(st.global.active_sub, "a");
	assertEq(st.selected, "a/a1");
});

test("subscriptionAdd leaves nothing behind when the fetch fails", function() {
	let st = state();
	let r = hsub.subscriptionAdd(mockCtx(st), { name: "Reserve", url: URL });
	assertEq(r, { error: "fetch failed" });
	assertEq(ids(st), [ "a" ]);
	assertEq(tags(st.servers), [ "a1" ]);
});

test("subscriptionAdd leaves nothing behind when no servers are parsed", function() {
	let st = state();
	st.fetched[URL] = { body: "garbage", userinfo: "total=1" };
	assertEq(hsub.subscriptionAdd(mockCtx(st), { name: "Reserve", url: URL }).error, "no servers parsed");
	assertEq(ids(st), [ "a" ]);
	assertEq(st.userinfo, {});
});

test("subscriptionAdd rejects a missing or non-http url before touching the config", function() {
	for (let bad in [ null, "", "  ", "ftp://panel/sub", "panel/sub", "https://", "https://pa nel/sub" ]) {
		let st = state();
		let r = hsub.subscriptionAdd(mockCtx(st), { name: "x", url: bad });
		assert(r.error == "no subscription url" || r.error == "invalid subscription url", "url " + bad + " -> " + r.error);
		assertEq(ids(st), [ "a" ]);
	}
	assertEq(hsub.subscriptionAdd(mockCtx(state()), null).error, "no subscription url");
});

test("subscriptionAdd retries a taken id and names an unnamed subscription", function() {
	let st = state();
	push(st.subs, sub("sub_11111111"));
	st.hex = [ "11111111", "22222222" ];
	st.fetched[URL] = { body: BODY, userinfo: "" };
	let r = hsub.subscriptionAdd(mockCtx(st), { url: URL });
	assertEq(r.sub, "sub_22222222");
	assertEq(st.subs[2].name, "Subscription");
});

test("subscriptionAdd makes the new one active when the active one is empty", function() {
	let st = mkState([ manual("m1", "1.0.0.9") ], [ sub("subscription", { url: "" }) ], "subscription");
	st.fetched[URL] = { body: BODY, userinfo: "" };
	st.hex = [ "0badc0de" ];
	let r = hsub.subscriptionAdd(mockCtx(st), { name: "Main", url: URL });
	assertEq(r.active_sub, "sub_0badc0de");
	assertEq(st.global.active_sub, "sub_0badc0de");
	assertEq(ids(st), [ "sub_0badc0de" ]);
});

test("subscriptionAdd keeps the empty active one when switching fails", function() {
	let st = mkState([], [ sub("subscription", { url: "" }) ], "subscription");
	st.fetched[URL] = { body: BODY, userinfo: "" };
	st.hex = [ "0badc0de" ];
	st.setFail = true;
	let r = hsub.subscriptionAdd(mockCtx(st), { name: "Main", url: URL });
	assertEq(r.active_sub, null);
	assertEq(ids(st), [ "subscription", "sub_0badc0de" ]);
});

test("subscriptionAdd keeps a non-empty active one", function() {
	let st = mkState([], [ sub("main", { url: "https://a.example/s" }) ], "main");
	st.fetched[URL] = { body: BODY, userinfo: "" };
	st.hex = [ "0badc0de" ];
	let r = hsub.subscriptionAdd(mockCtx(st), { name: "Second", url: URL });
	assertEq(r.active_sub, null);
	assertEq(st.global.active_sub, "main");
	assertEq(ids(st), [ "main", "sub_0badc0de" ]);
});

test("subscriptionAdd keeps the empty active one when the fetch fails", function() {
	let st = mkState([], [ sub("subscription", { url: "" }) ], "subscription");
	hsub.subscriptionAdd(mockCtx(st), { name: "Main", url: URL });
	assertEq(st.global.active_sub, "subscription");
	assertEq(st.writes, 0);
	assertEq(ids(st), [ "subscription" ]);
});

test("subscriptionAdd strips control characters and caps the name", function() {
	let st = state();
	st.fetched[URL] = { body: BODY, userinfo: "" };
	hsub.subscriptionAdd(mockCtx(st), { name: "Re\nser\tve", url: URL });
	assertEq(st.subs[1].name, "Reserve");
	let long = state();
	long.fetched[URL] = { body: BODY, userinfo: "" };
	hsub.subscriptionAdd(mockCtx(long), { name: sprintf("%070d", 1), url: URL });
	assertEq(length(long.subs[1].name), 64);
});

test("subscription urls are checked case-insensitively on add and update", function() {
	let st = state();
	st.fetched["HTTPS://panel/sub/token"] = { body: BODY, userinfo: "" };
	assertEq(hsub.subscriptionAdd(mockCtx(st), { url: "HTTPS://panel/sub/token" }).added, 1);
	let up = state();
	assertEq(hsub.subscriptionUpdate(mockCtx(up), { sub: "a", url: "-K/etc/passwd" }), { error: "invalid subscription url" });
	assertEq(up.urls, {});
});

exit(run());
