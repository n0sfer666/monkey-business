import { test, assert, assertEq, run } from "../harness.uc";
import * as h from "../../src/rpcd/handlers.uc";
import { readfile } from "fs";

const SUB = readfile("test/fixtures/sub_urilist.txt");

function mockCtx(state) {
	return {
		getGlobal: function() { return state.global; },
		getSubscription: function() { return state.subscription; },
		getServers: function() { return state.servers; },
		setServers: function(a) { state.servers = a; },
		getSelectedServer: function() {
			for (let s in state.servers)
				if (s.tag == state.selected)
					return s;
			return null;
		},
		fetchSubscription: function(_url) { return state.fetchResult; },
		pingServer: function(s) { return state.pings[s.tag]; },
		applyConfig: function(j) { state.applied = j; },
		serviceRunning: function() { return state.running; },
		setEnabled: function(b) { state.global.enabled = b ? "1" : "0"; },
		updateGeo: function() { return { status: "ok", files: ["geoip.dat", "geosite.dat"] }; },
	};
}

function freshState() {
	return {
		global: { enabled: "0", routing_mode: "bypass-local", local_region: "ru", tproxy_port: 12345 },
		subscription: { url: "https://example/sub" },
		servers: [],
		selected: null,
		pings: {},
		running: false,
		fetchResult: null,
		applied: null,
	};
}

test("maskUuid masks middle", function() {
	assertEq(h.maskUuid("11111111-2222-3333-4444-555555555555"), "1111..5555");
	assertEq(h.maskUuid("short"), "****");
});

test("status reflects state", function() {
	let st = freshState();
	st.global.enabled = "1";
	st.running = true;
	let r = h.status(mockCtx(st));
	assertEq(r.enabled, true);
	assertEq(r.running, true);
	assertEq(r.routing_mode, "bypass-local");
	assertEq(r.server, null);
});

test("subscriptionUpdate success stores servers", function() {
	let st = freshState();
	st.fetchResult = SUB;
	let ctx = mockCtx(st);
	let r = h.subscriptionUpdate(ctx, {});
	assertEq(r.format, "uri-list");
	assertEq(r.added, 2);
	assertEq(length(st.servers), 2);
});

test("subscriptionUpdate keeps old list on fetch failure", function() {
	let st = freshState();
	st.servers = [{ tag: "old", address: "x", port: 1, security: "tls", transport: { type: "tcp" }, uuid: "aaaaaaaa-bbbb" }];
	st.fetchResult = null;
	let r = h.subscriptionUpdate(mockCtx(st), {});
	assertEq(r.error, "fetch failed");
	assertEq(r.kept, 1);
	assertEq(length(st.servers), 1);
});

test("subscriptionUpdate reports empty parse without wiping", function() {
	let st = freshState();
	st.servers = [{ tag: "old", address: "x", port: 1, security: "tls", transport: { type: "tcp" }, uuid: "u" }];
	st.fetchResult = "not a subscription";
	let r = h.subscriptionUpdate(mockCtx(st), {});
	assertEq(r.error, "no servers parsed");
	assertEq(length(st.servers), 1);
});

test("serversList masks uuid", function() {
	let st = freshState();
	st.fetchResult = SUB;
	let ctx = mockCtx(st);
	h.subscriptionUpdate(ctx, {});
	let r = h.serversList(ctx);
	assertEq(length(r.servers), 2);
	assertEq(r.servers[0].uuid_masked, "1111..5555");
	assert(!exists(r.servers[0], "uuid"), "raw uuid not leaked");
});

test("configApply generates and applies when server selected", function() {
	let st = freshState();
	st.fetchResult = SUB;
	let ctx = mockCtx(st);
	h.subscriptionUpdate(ctx, {});
	st.selected = "Server A";
	let r = h.configApply(ctx);
	assertEq(r.ok, true);
	assert(r.bytes > 0, "non-empty config");
	assert(index(st.applied, "dokodemo-door") >= 0, "applied config has tproxy inbound");
});

test("configApply errors without selected server", function() {
	let st = freshState();
	st.fetchResult = SUB;
	let ctx = mockCtx(st);
	h.subscriptionUpdate(ctx, {});
	let r = h.configApply(ctx);
	assertEq(r.error, "no server selected");
});

test("serviceToggle sets enabled", function() {
	let st = freshState();
	let ctx = mockCtx(st);
	assertEq(h.serviceToggle(ctx, { enabled: true }).enabled, true);
	assertEq(st.global.enabled, "1");
	assertEq(h.serviceToggle(ctx, { enabled: false }).enabled, false);
	assertEq(st.global.enabled, "0");
});

test("serversPing picks best latency", function() {
	let st = freshState();
	st.fetchResult = SUB;
	let ctx = mockCtx(st);
	h.subscriptionUpdate(ctx, {});
	st.pings = { "Server A": 120, "Server B": 45 };
	let r = h.serversPing(ctx);
	assertEq(r.best, "Server B");
	assertEq(length(r.results), 2);
});

test("geoUpdate returns status", function() {
	assertEq(h.geoUpdate(mockCtx(freshState())).status, "ok");
});

exit(run());
