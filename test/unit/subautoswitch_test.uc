import { test, assert, assertEq, run } from "../harness.uc";
import * as h from "../../src/rpcd/handlers.uc";
import * as hstatus from "../../src/rpcd/status.uc";
import * as hsub from "../../src/rpcd/subscription.uc";
import { subscriptionAutoswitch } from "../../src/rpcd/autoswitch.uc";
import { LEGACY_SUB, subDeath } from "../../src/lib/subs.uc";
import { NOW, srv, manual, sub, tags, mkState, mockCtx } from "../subfixtures.uc";

const SPENT = { total: "100", used_upload: "60", used_download: "40" };
const GONE = { expire: "1" };

function threeSubs(a, b, c, active) {
	return mkState([ srv("a1", "1.1.1.1", "a"), srv("b1", "2.2.2.2", "b"), srv("c1", "3.3.3.3", "c") ],
		[ sub("a", a), sub("b", b), sub("c", c) ], active);
}

test("subDeath tells exhausted from expired and keeps unlimited alive", function() {
	assertEq(subDeath(sub("x", SPENT), NOW), "exhausted");
	assertEq(subDeath(sub("x", { expire: "" + NOW }), NOW), "expired");
	assert(subDeath(sub("x", { expire: "" + (NOW + 1), total: "0", used_download: "5" }), NOW) == null, "жива");
	assert(subDeath(sub("x", { total: "abc", expire: "junk" }), NOW) == null, "мусор не убивает");
});

test("exhausted active switches to the next alive one and applies", function() {
	let st = threeSubs(SPENT, {}, {}, "a");
	st.selected = "a/a1";
	let r = subscriptionAutoswitch(mockCtx(st), {});
	assertEq(r.ok, true);
	assertEq(r.active_sub, "b");
	assertEq(r.switched_from, "a");
	assertEq(r.reason, "exhausted");
	assertEq(r.applied, true);
	assertEq(st.global.active_sub, "b");
	assertEq(st.writes, 1);
	assertEq(st.applies, 1);
	assertEq(st.selected, "b/b1");
	assertEq(st.autoswitch, { from: "a", reason: "exhausted" });
});

test("expired active by time skips dead ones and wraps around", function() {
	let st = threeSubs({}, GONE, SPENT, "b");
	let r = subscriptionAutoswitch(mockCtx(st), {});
	assertEq(r.active_sub, "a");
	assertEq(r.reason, "expired");
	assertEq(st.global.active_sub, "a");
});

test("unset active_sub means the first subscription", function() {
	let st = threeSubs(SPENT, {}, {}, null);
	assertEq(subscriptionAutoswitch(mockCtx(st), {}).active_sub, "b");
});

test("no alive alternative: no write on this tick nor on the next ones", function() {
	let st = threeSubs(SPENT, GONE, SPENT, "a");
	for (let i = 0; i < 3; i++) {
		let r = subscriptionAutoswitch(mockCtx(st), {});
		assertEq(r.dead, "exhausted");
		assert(r.switch_to == null, "переключаться некуда");
	}
	assertEq(st.writes, 0);
	assertEq(st.applies, 0);
	assertEq(st.global.active_sub, "a");
	assert(st.autoswitch == null, "причина не пишется");
});

test("repeated tick after a switch writes nothing", function() {
	let st = threeSubs(SPENT, {}, {}, "a");
	subscriptionAutoswitch(mockCtx(st), {});
	let r = subscriptionAutoswitch(mockCtx(st), {});
	assertEq(r, { ok: true, active_sub: "b" });
	assertEq(st.writes, 1);
	assertEq(st.applies, 1);
});

test("alive active is left alone", function() {
	let st = threeSubs({}, SPENT, {}, "a");
	assertEq(subscriptionAutoswitch(mockCtx(st), {}), { ok: true, active_sub: "a" });
	assertEq(st.writes, 0);
});

test("check mode reports the target without writing or applying", function() {
	let st = threeSubs(SPENT, {}, {}, "a");
	let r = subscriptionAutoswitch(mockCtx(st), { check: true });
	assertEq(r.switch_to, "b");
	assertEq(r.dead, "exhausted");
	assertEq(st.writes, 0);
	assertEq(st.applies, 0);
	assertEq(st.global.active_sub, "a");
});

test("tunnel already off the dead subscription: record the choice, keep the tunnel", function() {
	for (let sel in [ "c/c1", "m1" ]) {
		let st = threeSubs(SPENT, {}, {}, "a");
		push(st.servers, manual("m1", "9.9.9.9"));
		st.selected = sel;
		let r = subscriptionAutoswitch(mockCtx(st), {});
		assertEq(r.active_sub, "b");
		assertEq(r.applied, false);
		assertEq(st.applies, 0);
		assertEq(st.selected, sel);
		assertEq(st.autoswitch, { from: "a", reason: "exhausted" });
	}
});

test("deadline passed in the rpcd queue: nothing is written", function() {
	let st = threeSubs(SPENT, {}, {}, "a");
	let r = subscriptionAutoswitch(mockCtx(st), { deadline: NOW });
	assert(index(r.error, "deadline") >= 0, "отказ по дедлайну");
	assertEq(st.writes, 0);
	assertEq(st.applies, 0);
});

test("apply failure keeps the switch, so the next tick does not write again", function() {
	let st = threeSubs(SPENT, {}, {}, "a");
	st.applyErr = "xray -test failed";
	let r = subscriptionAutoswitch(mockCtx(st), { deadline: NOW + 75 });
	assertEq(r.error, "xray -test failed");
	assertEq(r.active_sub, "b");
	assertEq(st.global.active_sub, "b");
	subscriptionAutoswitch(mockCtx(st), {});
	assertEq(st.writes, 1);
});

test("failed commit reports an error and records no reason", function() {
	let st = threeSubs(SPENT, {}, {}, "a");
	st.setFail = true;
	assert(index(subscriptionAutoswitch(mockCtx(st), {}).error, "read-only") >= 0, "ошибка записи");
	assert(st.autoswitch == null, "причины нет");
	assertEq(st.applies, 0);
});

test("VPN off: the switch is recorded without applying", function() {
	let st = threeSubs(SPENT, {}, {}, "a");
	st.global.enabled = "0";
	let r = subscriptionAutoswitch(mockCtx(st), {});
	assertEq(r.active_sub, "b");
	assertEq(r.applied, false);
	assertEq(st.applies, 0);
});

test("status shows the autoswitch reason, a manual choice clears it", function() {
	let st = threeSubs(SPENT, {}, {}, "a");
	subscriptionAutoswitch(mockCtx(st), {});
	assertEq(hstatus.status(mockCtx(st)).autoswitch, { from: "a", reason: "exhausted" });
	h.subscriptionSelect(mockCtx(st), { sub: "b" });
	assert(hstatus.status(mockCtx(st)).autoswitch == null, "выбор того же стирает плашку");
	st.autoswitch = { from: "a", reason: "exhausted" };
	h.subscriptionSelect(mockCtx(st), { sub: "c" });
	assert(st.autoswitch == null, "ручное переключение стирает плашку");
});

test("failed manual switch keeps the autoswitch reason", function() {
	let st = threeSubs({}, {}, {}, "a");
	st.autoswitch = { from: "c", reason: "expired" };
	st.applyErr = "xray -test failed";
	h.subscriptionSelect(mockCtx(st), { sub: "b" });
	assertEq(st.autoswitch, { from: "c", reason: "expired" });
});

test("manual choice of a dead subscription is refused while an alive one exists", function() {
	let st = threeSubs({}, SPENT, {}, "a");
	let r = h.subscriptionSelect(mockCtx(st), { sub: "b" });
	assert(index(r.error, "exhausted") >= 0, "отказ с причиной");
	assertEq(st.writes, 0);
	assertEq(st.applies, 0);
	assertEq(st.global.active_sub, "a");
});

test("manual choice of a dead subscription is allowed when all are dead", function() {
	let st = threeSubs(SPENT, GONE, SPENT, "a");
	assertEq(h.subscriptionSelect(mockCtx(st), { sub: "b" }).active_sub, "b");
	assertEq(st.global.active_sub, "b");
	assertEq(subscriptionAutoswitch(mockCtx(st), {}).switch_to, null);
});

const BODY = "vless://u@4.4.4.4:443?security=none&type=tcp#fresh";

test("subscriptionUpdate {sub} merges into its own slice and stores url and userinfo there", function() {
	let st = threeSubs({ url: "https://a/sub" }, {}, {}, "a");
	st.fetched["https://a/sub"] = { body: BODY, userinfo: "upload=1; download=2; total=3; expire=4" };
	let r = hsub.subscriptionUpdate(mockCtx(st), { sub: "a" });
	assertEq(r.added, 1);
	assertEq(tags(st.servers), [ "b1", "c1", "fresh" ]);
	assertEq(st.servers[2].sub, "a");
	assertEq(st.urls, { a: "https://a/sub" });
	assertEq(st.userinfo.a.total, "3");
});

test("subscriptionUpdate rejects an unknown subscription, defaults to the legacy one", function() {
	let st = threeSubs({}, {}, {}, "a");
	assertEq(hsub.subscriptionUpdate(mockCtx(st), { sub: "zzz" }).error, "unknown subscription");
	push(st.subs, sub(LEGACY_SUB, { url: "https://legacy/sub" }));
	st.fetched["https://legacy/sub"] = { body: BODY, userinfo: "" };
	hsub.subscriptionUpdate(mockCtx(st), {});
	assertEq(st.servers[3].sub, LEGACY_SUB);
	assertEq(st.urls[LEGACY_SUB], "https://legacy/sub");
});

exit(run());
