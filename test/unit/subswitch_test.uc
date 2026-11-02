import { test, assert, assertEq, run } from "../harness.uc";
import * as h from "../../src/rpcd/handlers.uc";
import * as hstatus from "../../src/rpcd/status.uc";
import { srv, manual, sub, ids, mkState, mockCtx } from "../subfixtures.uc";

function twoSubs() {
	return mkState([ srv("a1", "1.1.1.1", "a"), srv("b1", "2.2.2.2", "b") ], [ sub("a"), sub("b") ], "a");
}

test("same tag in two subscriptions: selection and status follow the subscription", function() {
	let st = mkState([ srv("nl", "1.1.1.1", "a"), srv("nl", "2.2.2.2", "b") ], [ sub("a"), sub("b") ], "a");
	st.probeFail["a/nl"] = true;
	let r = h.configApply(mockCtx(st));
	assertEq(r.probed, true);
	assertEq(r.server_id, "b/nl");
	assertEq(st.selected, "b/nl");
	assert(index(st.applied, "2.2.2.2") >= 0, "применён сервер подписки b");
	let s = hstatus.status(mockCtx(st));
	assertEq(s.server_id, "b/nl");
	assertEq(s.sub, "b");
	assertEq(s.active_sub, "a");
	assertEq(s.reserve, true);
});

test("configApply tells disabled servers apart from an empty list", function() {
	let off = srv("a1", "1.1.1.1", "a");
	off.disabled = "1";
	let st = mkState([ off ], [ sub("a") ], "a");
	let r = h.configApply(mockCtx(st));
	assert(index(r.error, "no usable servers") >= 0, "все выключены");
	assertEq(st.applies, 0);
	st.servers = [];
	assert(index(h.configApply(mockCtx(st)).error, "no servers —") == 0, "список пуст");
});

test("subscriptionSelect applies the new subscription", function() {
	let st = twoSubs();
	st.selected = "a/a1";
	let r = h.subscriptionSelect(mockCtx(st), { sub: "b" });
	assertEq(r.ok, true);
	assertEq(r.active_sub, "b");
	assertEq(st.global.active_sub, "b");
	assertEq(st.selected, "b/b1");
	assertEq(st.applies, 1);
});

test("subscriptionSelect rolls back the choice and the selection when apply fails", function() {
	let st = twoSubs();
	st.selected = "a/a1";
	st.applyErr = "xray -test failed";
	let r = h.subscriptionSelect(mockCtx(st), { sub: "b" });
	assertEq(r.error, "xray -test failed");
	assertEq(st.global.active_sub, "a");
	assertEq(st.selected, "a/a1");
});

test("subscriptionSelect rollback restores the raw selection, even an empty or legacy one", function() {
	let st = twoSubs();
	st.applyErr = "xray -test failed";
	h.subscriptionSelect(mockCtx(st), { sub: "b" });
	assertEq(st.selected, "");
	st.selected = "a1";
	h.subscriptionSelect(mockCtx(st), { sub: "b" });
	assertEq(st.selected, "a1");
});

test("subscriptionSelect with the VPN off only records the choice", function() {
	let st = twoSubs();
	st.global.enabled = "0";
	st.selected = "a/a1";
	let r = h.subscriptionSelect(mockCtx(st), { sub: "b" });
	assertEq(r.skipped, "disabled");
	assertEq(st.global.active_sub, "b");
	assertEq(st.applies, 0);
	assertEq(st.selected, "a/a1");
});

test("subscriptionSelect rejects an unknown subscription and skips a no-op", function() {
	let st = twoSubs();
	assertEq(h.subscriptionSelect(mockCtx(st), { sub: "zzz" }).error, "unknown subscription");
	assertEq(h.subscriptionSelect(mockCtx(st), {}).error, "unknown subscription");
	assertEq(h.subscriptionSelect(mockCtx(st), { sub: "a" }).unchanged, true);
	st.global.active_sub = null;
	assertEq(h.subscriptionSelect(mockCtx(st), { sub: "a" }).unchanged, true);
	assertEq(st.writes, 0);
	assertEq(st.applies, 0);
});

test("subscriptionSelect reports a failed commit without applying", function() {
	let st = twoSubs();
	st.setFail = true;
	let r = h.subscriptionSelect(mockCtx(st), { sub: "b" });
	assert(index(r.error, "read-only") >= 0, "ошибка записи");
	assertEq(st.applies, 0);
});

test("status shows traffic of the subscription carrying the tunnel", function() {
	let st = mkState([ srv("a1", "1.1.1.1", "a"), srv("b1", "2.2.2.2", "b"), manual("m1", "9.9.9.9") ],
		[ sub("a", { total: "100" }), sub("b", { total: "200", expire: "1" }) ], "a");
	st.selected = "b/b1";
	let s = hstatus.status(mockCtx(st));
	assertEq(s.traffic.total, "200");
	assertEq(s.subscriptions, [ { id: "a", name: "N-a", alive: true }, { id: "b", name: "N-b", alive: false } ]);
	st.selected = "m1";
	s = hstatus.status(mockCtx(st));
	assertEq(s.traffic.total, "100");
	assert(s.sub == null, "ручной сервер не принадлежит подписке");
	assertEq(s.reserve, false);
});

test("serversList follows the group order and marks reserve and disabled", function() {
	let off = srv("a1", "1.1.1.1", "a");
	off.disabled = "1";
	let st = mkState([ srv("b1", "2.2.2.2", "b"), off, manual("m1", "9.9.9.9") ], [ sub("a"), sub("b") ], "a");
	let r = hstatus.serversList(mockCtx(st));
	assertEq(ids(r.servers), [ "a/a1", "m1", "b/b1" ]);
	assertEq(map(r.servers, function(s) { return s.reserve; }), [ false, false, true ]);
	assertEq(map(r.servers, function(s) { return s.disabled; }), [ true, false, false ]);
	assertEq(map(r.servers, function(s) { return s.sub; }), [ "a", null, "b" ]);
	assertEq(r.active_sub, "a");
});

exit(run());
