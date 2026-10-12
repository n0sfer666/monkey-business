import { test, assert, assertEq, run } from "../harness.uc";
import { serverConnect } from "../../src/rpcd/connect.uc";
import { srv, manual, sub, tags, mkState, mockCtx } from "../subfixtures.uc";

function state() {
	return mkState([ srv("a1", "1.1.1.1", "a"), manual("m1", "3.3.3.3"), srv("a2", "1.1.1.2", "a"),
		srv("b1", "2.2.2.1", "b"), srv("b2", "2.2.2.2", "b") ], [ sub("a"), sub("b") ], "a");
}

test("serverConnect moves the server first and applies it", function() {
	let st = state();
	st.selected = "a/a1";
	let r = serverConnect(mockCtx(st), { id: "a/a2" });
	assertEq(r.ok, true);
	assertEq(r.server_id, "a/a2");
	assertEq(tags(st.servers), [ "a2", "a1", "m1", "b1", "b2" ]);
	assertEq(st.selected, "a/a2");
	assertEq(st.applies, 1);
	assertEq(st.global.active_sub, "a");
});

test("serverConnect on a reserve server makes its subscription active", function() {
	let st = state();
	st.autoswitch = { from: "a", reason: "expired" };
	let r = serverConnect(mockCtx(st), { id: "b/b2" });
	assertEq(r.server_id, "b/b2");
	assertEq(st.global.active_sub, "b");
	assertEq(tags(st.servers)[0], "b2");
	assertEq(st.autoswitch, null);
});

test("serverConnect rolls back order, subscription and selection when apply fails", function() {
	let st = state();
	st.selected = "a/a1";
	st.applyErr = "xray -test failed";
	let r = serverConnect(mockCtx(st), { id: "b/b2" });
	assertEq(r.error, "xray -test failed");
	assertEq(tags(st.servers), [ "a1", "m1", "a2", "b1", "b2" ]);
	assertEq(st.global.active_sub, "a");
	assertEq(st.selected, "a/a1");
});

test("serverConnect restores the order when the subscription choice does not save", function() {
	let st = state();
	st.setFail = true;
	let r = serverConnect(mockCtx(st), { id: "b/b1" });
	assert(index(r.error, "could not save") == 0, "ошибка записи");
	assertEq(tags(st.servers), [ "a1", "m1", "a2", "b1", "b2" ]);
	assertEq(st.applies, 0);
});

test("serverConnect with the VPN off only records the order", function() {
	let st = state();
	st.global.enabled = "0";
	let r = serverConnect(mockCtx(st), { id: "m1" });
	assertEq(r.skipped, "disabled");
	assertEq(tags(st.servers)[0], "m1");
	assertEq(st.applies, 0);
});

test("serverConnect refuses an off server, an unknown id and a dead reserve", function() {
	let st = state();
	st.servers[2].disabled = "1";
	assert(index(serverConnect(mockCtx(st), { id: "a/a2" }).error, "server is off") == 0, "off");
	assertEq(serverConnect(mockCtx(st), { id: "zzz" }).error, "unknown server");
	assertEq(serverConnect(mockCtx(st), null).error, "unknown server");
	st.subs[1].expire = "1";
	assert(index(serverConnect(mockCtx(st), { id: "b/b1" }).error, "subscription is expired") == 0, "dead");
	assertEq(st.applies, 0);
	assertEq(st.global.active_sub, "a");
});

test("serverConnect skips a no-op on the server already in use", function() {
	let st = state();
	st.selected = "a/a1";
	let r = serverConnect(mockCtx(st), { id: "a/a1" });
	assertEq(r.unchanged, true);
	assertEq(st.applies, 0);
});

test("serverConnect skips a no-op when the server leads by effective priority, not by index", function() {
	let st = state();
	st.servers[0].disabled = "1";
	st.selected = "m1";
	let r = serverConnect(mockCtx(st), { id: "m1" });
	assertEq(r.unchanged, true);
	assertEq(tags(st.servers), [ "a1", "m1", "a2", "b1", "b2" ]);
	assertEq(st.applies, 0);
});

test("serverConnect reconnects the leading server when the VPN is down or off", function() {
	let st = state();
	st.selected = "a/a1";
	st.running = false;
	let r = serverConnect(mockCtx(st), { id: "a/a1" });
	assertEq(r.unchanged, null);
	assertEq(st.applies, 1);
	st.global.enabled = "0";
	r = serverConnect(mockCtx(st), { id: "a/a1" });
	assertEq(r.skipped, "disabled");
	assertEq(st.applies, 1);
});

test("serverConnect refuses a hysteria server without the client", function() {
	let st = state();
	st.servers[2].protocol = "hysteria2";
	let ctx = mockCtx(st);
	ctx.hysteriaInstalled = function() { return false; };
	assert(index(serverConnect(ctx, { id: "a/a2" }).error, "hysteria client is not installed") == 0, "no client");
	assertEq(tags(st.servers), [ "a1", "m1", "a2", "b1", "b2" ]);
	assertEq(st.applies, 0);
});

test("serverConnect stops when the order does not save", function() {
	let st = state();
	st.serversFail = true;
	let r = serverConnect(mockCtx(st), { id: "a/a2" });
	assert(index(r.error, "could not save the server order") == 0, "order write");
	assertEq(st.global.active_sub, "a");
	assertEq(st.applies, 0);
});

exit(run());
