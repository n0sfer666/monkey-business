import { test, assert, assertEq, run } from "../harness.uc";
import * as h from "../../src/rpcd/handlers.uc";
import * as hsel from "../../src/rpcd/select.uc";
import * as hping from "../../src/rpcd/ping.uc";
import * as hstatus from "../../src/rpcd/status.uc";
import { PING_LIMIT_MS, pingView } from "../../src/rpcd/latency.uc";
import { NOW, PING_COST, srv, manual, sub, mkState, mockCtx } from "../subfixtures.uc";

function hy(tag, address, s) {
	let x = srv(tag, address, s);
	x.protocol = "hysteria2";
	return x;
}

function threeA() {
	return mkState([ srv("a1", "1.0.0.1", "a"), srv("a2", "1.0.0.2", "a"), srv("a3", "1.0.0.3", "a") ],
		[ sub("a") ], "a");
}

test("rotation probes only servers that answered the ping within the limit", function() {
	let st = threeA();
	st.pingDown = { "a/a1": true };
	st.pingMs = { "a/a2": PING_LIMIT_MS + 1 };
	let r = hsel.selectWorking(mockCtx(st));
	assertEq(st.pingLimit, PING_LIMIT_MS);
	assertEq(st.probed, [ "a3" ]);
	assertEq(r.probed, true);
	assertEq(st.selected, "a/a3");
	assertEq(st.pingStore["a/a1"], { ms: null });
	assertEq(st.pingStore["a/a3"], { ms: 50 });
});

test("all filtered out by ping: fall back to every candidate in order", function() {
	let st = threeA();
	st.pingDown = { "a/a1": true, "a/a2": true, "a/a3": true };
	st.probeFail = { "a/a1": true };
	let r = hsel.selectWorking(mockCtx(st));
	assertEq(st.probed, [ "a1", "a2" ]);
	assertEq(st.selected, "a/a2");
	assertEq(r.probed, true);
});

test("hysteria2 is never pinged and never filtered out", function() {
	let st = mkState([ srv("a1", "1.0.0.1", "a"), hy("h1", "1.0.0.9", "a"), srv("a2", "1.0.0.2", "a") ],
		[ sub("a") ], "a");
	st.pingDown = { "a/a1": true };
	hsel.selectWorking(mockCtx(st));
	assertEq(st.pinged, [ [ "a1", "a2" ] ]);
	assertEq(st.probed, [ "h1" ]);
	assertEq(st.pingStore["a/h1"], null);
	assertEq(pingView(st.pingStore, hy("h1", "1.0.0.9", "a")), { latency_ms: null, na: true, auto_disabled: false });
});

test("hysteria2 alone does not count as a ping survivor: every TCP server down means the full list", function() {
	let st = mkState([ srv("a1", "1.0.0.1", "a"), hy("h1", "1.0.0.9", "a") ], [ sub("a") ], "a");
	st.pingDown = { "a/a1": true };
	st.probeFail = { "a/a1": true };
	hsel.selectWorking(mockCtx(st));
	assertEq(st.probed, [ "a1", "h1" ]);
	assertEq(st.selected, "a/h1");
});

test("a manually disabled server is pinged and listed but not a candidate, even in the fallback", function() {
	let off = manual("m1", "9.0.0.1");
	off.disabled = "1";
	let st = mkState([ off, srv("a1", "1.0.0.1", "a") ], [ sub("a") ], "a");
	st.pingDown = { "a/a1": true };
	st.probeFail = { "a/a1": true };
	let r = hsel.selectWorking(mockCtx(st));
	assertEq(st.probed, [ "a1" ]);
	assertEq(r.server.tag, "a1");
	assertEq(r.probed, false);
	let p = hping.serversPing(mockCtx(st));
	assertEq(map(p.results, function(x) { return x.id; }), [ "m1", "a/a1" ]);
	assertEq(p.best_id, "m1");
});

test("failover_cap counts only servers that passed the ping", function() {
	let st = threeA();
	st.cap = 1;
	st.pingDown = { "a/a1": true };
	hsel.selectWorking(mockCtx(st));
	assertEq(st.probed, [ "a2" ]);
	assertEq(st.selected, "a/a2");
});

test("deadline: a probe that cannot finish before it is not started", function() {
	let st = threeA();
	st.probeFail = { "a/a1": true, "a/a2": true, "a/a3": true };
	let cost = hsel.probeCost(st.servers[0]);
	let r = h.configApply(mockCtx(st), { deadline: NOW + PING_COST + 10 + cost + 1 });
	assertEq(st.probed, [ "a1", "a2" ]);
	assertEq(r.ok, true);
	assertEq(r.probed, false);
	assertEq(st.selected, "a/a1");
});

test("deadline shorter than one probe: nothing is probed, the first candidate is applied", function() {
	let st = threeA();
	let r = h.configApply(mockCtx(st), { deadline: NOW + PING_COST + 5 });
	assertEq(st.probed, []);
	assertEq([ r.ok, r.probed ], [ true, false ]);
	assertEq(st.applies, 1);
});

test("deadline already passed when config_apply starts: nothing is pinged, probed or applied", function() {
	let st = threeA();
	let r = h.configApply(mockCtx(st), { deadline: NOW });
	assert(r.error != null, "истёкший дедлайн");
	assertEq([ st.pinged, st.probed, st.applies ], [ [], [], 0 ]);
});

test("hysteria2 probes cost more than TCP ones", function() {
	assert(hsel.probeCost(hy("h1", "1.0.0.9", "a")) > hsel.probeCost(srv("a1", "1.0.0.1", "a")), "hysteria дороже");
});

test("the ping store keeps only servers that still exist", function() {
	let st = threeA();
	st.pingStore = { "a/gone": { ms: 30 }, "a/a2": { ms: 70 } };
	hping.serverPing(mockCtx(st), { id: "a/a1" });
	assertEq(st.pingStore, { "a/a2": { ms: 70 }, "a/a1": { ms: 50 } });
});

test("no deadline means every candidate is probed", function() {
	let st = threeA();
	st.probeFail = { "a/a1": true, "a/a2": true, "a/a3": true };
	h.configApply(mockCtx(st), {});
	assertEq(st.probed, [ "a1", "a2", "a3" ]);
	st.probed = [];
	hsel.selectWorking(mockCtx(st));
	assertEq(st.probed, [ "a1", "a2", "a3" ]);
});

test("auto-disable: unanswered or over the limit; lifted by the next successful ping", function() {
	let s = srv("a1", "1.0.0.1", "a");
	assertEq(pingView({}, s).auto_disabled, false);
	assertEq(pingView({ "a/a1": { ms: PING_LIMIT_MS } }, s).auto_disabled, false);
	assertEq(pingView({ "a/a1": { ms: PING_LIMIT_MS + 1 } }, s).auto_disabled, true);
	assertEq(pingView({ "a/a1": { ms: null } }, s).auto_disabled, true);
	let st = threeA();
	st.pingStore = { "a/a1": { ms: null } };
	assertEq(hstatus.serversList(mockCtx(st)).servers[0].auto_disabled, true);
	st.pingMs = { "a/a1": 40 };
	let r = hping.serverPing(mockCtx(st), { id: "a/a1" });
	assertEq(r.auto_disabled, false);
	assertEq(r.latency_ms, 40);
	let row = hstatus.serversList(mockCtx(st)).servers[0];
	assertEq([ row.auto_disabled, row.latency_ms, row.ping_na ], [ false, 40, false ]);
});

test("subscription ping covers only that subscription; unknown targets are errors", function() {
	let st = mkState([ srv("nl", "1.0.0.1", "a"), manual("m1", "9.0.0.1"), srv("nl", "2.0.0.1", "b") ],
		[ sub("a"), sub("b") ], "a");
	let r = hping.subscriptionPing(mockCtx(st), { sub: "b" });
	assertEq(st.pinged, [ [ "nl" ] ]);
	assertEq(map(r.results, function(x) { return x.id; }), [ "b/nl" ]);
	assertEq(st.pingStore, { "b/nl": { ms: 50 } });
	assert(hping.subscriptionPing(mockCtx(st), { sub: "gone" }).error != null, "неизвестная подписка");
	assert(hping.serverPing(mockCtx(st), { id: "c/nl" }).error != null, "неизвестный сервер");
	assertEq(length(st.pinged), 1);
});

test("server ping keys by identity: same tag in two subscriptions", function() {
	let st = mkState([ srv("nl", "1.0.0.1", "a"), srv("nl", "2.0.0.1", "b") ], [ sub("a"), sub("b") ], "a");
	st.pingDown = { "b/nl": true };
	let r = hping.serverPing(mockCtx(st), { id: "b/nl" });
	assertEq([ r.id, r.auto_disabled ], [ "b/nl", true ]);
	assertEq(st.pingStore, { "b/nl": { ms: null } });
});

exit(run());
