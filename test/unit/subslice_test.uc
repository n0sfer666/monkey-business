import { test, assert, assertEq, run } from "../harness.uc";
import * as hsub from "../../src/rpcd/subscription.uc";
import { LEGACY_SUB, serverSub } from "../../src/lib/subs.uc";
import { reviveServer, flattenServer } from "../../src/lib/servermap.uc";

function srv(tag, address, sub) {
	let s = { tag: tag, protocol: "vless", address: address, port: 443, uuid: "u-" + address,
		security: "none", sni: "", alpn: [], reality: null,
		transport: { type: "tcp", path: "", host: "", mode: "", serviceName: "" },
		source: "subscription" };
	if (sub != null)
		s.sub = sub;
	return s;
}

function manual(tag, address) {
	let s = srv(tag, address, null);
	s.source = "manual";
	return s;
}

function tags(list) {
	return map(list, function(s) { return s.tag; });
}

function subs(list) {
	return map(list, function(s) { return s.sub; });
}

test("merge of one subscription keeps another subscription's servers in place", function() {
	let existing = [ srv("a1", "1.1.1.1", "a"), srv("b1", "2.2.2.2", "b"), srv("a2", "1.1.1.2", "a") ];
	let fresh = [ srv("a2", "1.1.1.2"), srv("a3", "1.1.1.3") ];
	let out = hsub.mergeKeepingOrder(existing, fresh, "a");
	assertEq(tags(out), [ "b1", "a2", "a3" ]);
	assertEq(subs(out), [ "b", "a", "a" ]);
});

test("merge of one subscription keeps manual servers and the other slice untouched", function() {
	let b1 = srv("b1", "2.2.2.2", "b");
	let mine = manual("mine", "9.9.9.9");
	let existing = [ mine, srv("a1", "1.1.1.1", "a"), b1 ];
	let out = hsub.mergeKeepingOrder(existing, [ srv("b2", "2.2.2.3") ], "b");
	assertEq(tags(out), [ "mine", "a1", "b2" ]);
	assertEq(out[0], mine);
	assertEq(out[0].sub, null);
});

test("merge attributes a legacy server without sub to the legacy subscription", function() {
	let existing = [ srv("old", "3.3.3.3"), srv("b1", "2.2.2.2", "b") ];
	let out = hsub.mergeKeepingOrder(existing, [ srv("old", "3.3.3.3"), srv("new", "3.3.3.4") ], LEGACY_SUB);
	assertEq(tags(out), [ "old", "b1", "new" ]);
	assertEq(subs(out), [ LEGACY_SUB, "b", LEGACY_SUB ]);
});

test("merge of another subscription keeps legacy servers without sub", function() {
	let existing = [ srv("old", "3.3.3.3"), srv("b1", "2.2.2.2", "b") ];
	let out = hsub.mergeKeepingOrder(existing, [ srv("b1", "2.2.2.2") ], "b");
	assertEq(tags(out), [ "old", "b1" ]);
});

test("merge keeps the same server offered by two subscriptions as two candidates", function() {
	let existing = [ srv("nl", "4.4.4.4", "a") ];
	let out = hsub.mergeKeepingOrder(existing, [ srv("nl", "4.4.4.4") ], "b");
	assertEq(tags(out), [ "nl", "nl" ]);
	assertEq(subs(out), [ "a", "b" ]);
});

test("merge still skips a fresh server that duplicates a manual one", function() {
	let copy = manual("renamed", "5.5.5.5");
	let out = hsub.mergeKeepingOrder([ copy ], [ srv("x", "5.5.5.5") ], "a");
	assertEq(tags(out), [ "renamed" ]);
});

test("subscriptionUpdate leaves servers of a second subscription alone", function() {
	let st = {
		subscription: { url: "https://example/sub" },
		servers: [ srv("b1", "2.2.2.2", "b"), srv("old", "3.3.3.3") ],
		selected: "b1",
	};
	let ctx = {
		getSubscription: function() { return st.subscription; },
		getServers: function() { return st.servers; },
		setServers: function(a) { st.servers = a; },
		getSelectedServer: function() { return null; },
		setSelected: function(t) { st.selected = t; },
		setSubscriptionUrl: function(u) { st.subscription.url = u; },
		setUserinfo: function(_o) {},
		fetchSubscription: function(_u) {
			return { body: "vless://u@3.3.3.4:443?security=none&type=tcp#fresh", userinfo: "" };
		},
	};
	hsub.subscriptionUpdate(ctx, {});
	assertEq(tags(st.servers), [ "b1", "fresh" ]);
	assertEq(subs(st.servers), [ "b", LEGACY_SUB ]);
});

test("serverSub: explicit sub, legacy fallback, manual has none", function() {
	assertEq(serverSub(srv("t", "a", "sub_1f")), "sub_1f");
	assertEq(serverSub(srv("t", "a", "")), LEGACY_SUB);
	assertEq(serverSub(srv("t", "a")), LEGACY_SUB);
	assertEq(serverSub(manual("t", "a")), null);
	assertEq(serverSub({ tag: "no-source" }), null);
});

test("revive attributes legacy subscription servers and leaves manual ones bare", function() {
	let legacy = reviveServer({ tag: "t", protocol: "vless", address: "a", port: "443", source: "subscription" });
	assertEq(legacy.sub, LEGACY_SUB);
	let own = reviveServer({ tag: "t", protocol: "vless", address: "a", port: "443", source: "subscription", sub: "sub_2a" });
	assertEq(own.sub, "sub_2a");
	let hand = reviveServer({ tag: "t", protocol: "vless", address: "a", port: "443" });
	assert(hand.sub == null, "ручной сервер не принадлежит подписке");
});

test("revive drops a stale sub from a server turned manual by a pasted link", function() {
	let s = reviveServer({ tag: "t", protocol: "vless", address: "a", port: "443", source: "manual", sub: "sub_x" });
	assert(s.sub == null, "ручной сервер не принадлежит подписке");
	assert(!("sub" in flattenServer(s)), "устаревший sub не возвращается в UCI");
});

exit(run());
