import { test, assert, assertEq, run } from "../harness.uc";
import * as h from "../../src/rpcd/handlers.uc";
import { readfile } from "fs";

const SUB = readfile("test/fixtures/sub_urilist.txt");
const USERINFO = "upload=10; download=20; total=300; expire=1796738263";

function mockCtx(state) {
	return {
		getGlobal: function() { return state.global; },
		getDns: function() { return state.dns; },
		getAntiDpi: function() { return state.anti_dpi; },
		getSubscription: function() { return state.subscription; },
		getServers: function() { return state.servers; },
		setServers: function(a) { state.servers = a; },
		getSelectedServer: function() {
			for (let s in state.servers)
				if (s.tag == state.selected)
					return s;
			return null;
		},
		setSelected: function(tag) { state.selected = tag; },
		setSubscriptionUrl: function(u) { state.subscription.url = u; },
		setUserinfo: function(o) {
			state.subscription.used_upload = o.used_upload;
			state.subscription.used_download = o.used_download;
			state.subscription.total = o.total;
			state.subscription.expire = o.expire;
		},
		fetchSubscription: function(_url) { return state.fetchResult; },
		pingServer: function(s) { return state.pings[s.tag]; },
		applyConfig: function(j) { state.applied = j; return state.applyErr; },
		stopService: function() { state.stopped = true; },
		serviceRunning: function() { return state.running; },
		setEnabled: function(b) { state.global.enabled = b ? "1" : "0"; },
		updateGeo: function() { return { status: "ok", files: ["geoip.dat", "geosite.dat"] }; },
	};
}

function freshState() {
	return {
		global: { enabled: "0", routing_mode: "bypass-local", local_region: "ru", tproxy_port: 12345 },
		dns: { mode: "split", direct_dns: "223.5.5.5", doh_url: "https://1.1.1.1/dns-query" },
		anti_dpi: { default_fingerprint: "chrome", xhttp_padding: "0" },
		subscription: { url: "https://example/sub" },
		servers: [],
		selected: null,
		pings: {},
		running: false,
		fetchResult: null,
		applyErr: null,
		applied: null,
		stopped: false,
	};
}

test("maskUuid masks middle", function() {
	assertEq(h.maskUuid("11111111-2222-3333-4444-555555555555"), "1111..5555");
	assertEq(h.maskUuid("short"), "****");
});

test("parseUserinfo extracts traffic fields", function() {
	let u = h.parseUserinfo(USERINFO);
	assertEq(u.used_upload, "10");
	assertEq(u.used_download, "20");
	assertEq(u.total, "300");
	assertEq(u.expire, "1796738263");
	let empty = h.parseUserinfo("");
	assertEq(empty.total, "");
});

test("status reflects state and exposes traffic", function() {
	let st = freshState();
	st.global.enabled = "1";
	st.running = true;
	st.subscription.used_download = "20";
	st.subscription.total = "300";
	let r = h.status(mockCtx(st));
	assertEq(r.enabled, true);
	assertEq(r.running, true);
	assertEq(r.routing_mode, "bypass-local");
	assertEq(r.traffic.used_download, "20");
	assertEq(r.traffic.total, "300");
});

test("subscriptionUpdate stores servers, url, userinfo and auto-selects", function() {
	let st = freshState();
	st.fetchResult = { body: SUB, userinfo: USERINFO };
	let ctx = mockCtx(st);
	let r = h.subscriptionUpdate(ctx, { url: "https://new/sub" });
	assertEq(r.format, "uri-list");
	assertEq(r.added, 2);
	assertEq(length(st.servers), 2);
	assertEq(st.subscription.url, "https://new/sub");
	assertEq(st.subscription.total, "300");
	assert(st.selected != null, "auto-selected a server");
});

test("subscriptionUpdate preserves manual order on re-fetch", function() {
	let st = freshState();
	st.fetchResult = { body: SUB, userinfo: "" };
	let ctx = mockCtx(st);
	h.subscriptionUpdate(ctx, {});
	// эмулируем drag: реверс порядка
	st.servers = [ st.servers[1], st.servers[0] ];
	let firstTag = st.servers[0].tag;
	h.subscriptionUpdate(ctx, {});
	assertEq(st.servers[0].tag, firstTag);
	assertEq(length(st.servers), 2);
});

test("subscriptionUpdate falls back to saved url when arg empty", function() {
	let st = freshState();
	st.fetchResult = { body: SUB, userinfo: "" };
	let r = h.subscriptionUpdate(mockCtx(st), {});
	assertEq(r.added, 2);
});

test("subscriptionUpdate errors on empty url everywhere", function() {
	let st = freshState();
	st.subscription = {};
	let r = h.subscriptionUpdate(mockCtx(st), {});
	assertEq(r.error, "no subscription url");
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
	st.fetchResult = { body: "not a subscription", userinfo: "" };
	let r = h.subscriptionUpdate(mockCtx(st), {});
	assertEq(r.error, "no servers parsed");
	assertEq(length(st.servers), 1);
});

test("serversList masks uuid and exposes priority sorted", function() {
	let st = freshState();
	st.fetchResult = { body: SUB, userinfo: "" };
	let ctx = mockCtx(st);
	h.subscriptionUpdate(ctx, {});
	let r = h.serversList(ctx);
	assertEq(length(r.servers), 2);
	assertEq(r.servers[0].uuid_masked, "1111..5555");
	assertEq(r.servers[0].priority, 0);
	assert(!exists(r.servers[0], "uuid"), "raw uuid not leaked");
});

test("selectBest picks first reachable by priority", function() {
	let st = freshState();
	st.servers = [
		{ tag: "A", priority: "0", address: "a", port: 1 },
		{ tag: "B", priority: "1", address: "b", port: 2 },
		{ tag: "C", priority: "2", address: "c", port: 3 },
	];
	st.pings = { "A": null, "B": 50, "C": 20 };
	let chosen = h.selectBest(mockCtx(st));
	assertEq(chosen.tag, "B");
	assertEq(st.selected, "B");
});

test("selectBest falls back to first when none reachable", function() {
	let st = freshState();
	st.servers = [{ tag: "A", priority: "0", address: "a", port: 1 }, { tag: "B", priority: "1", address: "b", port: 2 }];
	st.pings = { "A": null, "B": null };
	assertEq(h.selectBest(mockCtx(st)).tag, "A");
});

test("configApply auto-selects and passes dns+anti_dpi", function() {
	let st = freshState();
	st.fetchResult = { body: SUB, userinfo: "" };
	st.anti_dpi.xhttp_padding = "1";
	let ctx = mockCtx(st);
	h.subscriptionUpdate(ctx, {});
	st.selected = null;
	let r = h.configApply(ctx);
	assertEq(r.ok, true);
	assert(st.selected != null, "auto-selected");
	assert(index(st.applied, "dokodemo-door") >= 0, "has tproxy inbound");
	assert(index(st.applied, "dns") >= 0, "dns applied");
});

test("configApply errors with no servers", function() {
	let st = freshState();
	let r = h.configApply(mockCtx(st));
	assert(index(r.error, "no servers") >= 0, "no-servers error");
});

test("configApply surfaces apply/validation error", function() {
	let st = freshState();
	st.fetchResult = { body: SUB, userinfo: "" };
	let ctx = mockCtx(st);
	h.subscriptionUpdate(ctx, {});
	st.applyErr = "xray: invalid config";
	let r = h.configApply(ctx);
	assertEq(r.error, "xray: invalid config");
});

test("serviceToggle on connects (selects+applies+enables)", function() {
	let st = freshState();
	st.fetchResult = { body: SUB, userinfo: "" };
	let ctx = mockCtx(st);
	h.subscriptionUpdate(ctx, {});
	st.selected = null;
	st.global.enabled = "0";
	let r = h.serviceToggle(ctx, { enabled: true });
	assertEq(r.enabled, true);
	assertEq(st.global.enabled, "1");
	assert(st.applied != null, "config applied on connect");
});

test("serviceToggle on without servers errors, stays off", function() {
	let st = freshState();
	let r = h.serviceToggle(mockCtx(st), { enabled: true });
	assertEq(r.enabled, false);
	assert(index(r.error, "no servers") >= 0, "error reported");
});

test("serviceToggle on surfaces apply error, stays off", function() {
	let st = freshState();
	st.fetchResult = { body: SUB, userinfo: "" };
	let ctx = mockCtx(st);
	h.subscriptionUpdate(ctx, {});
	st.applyErr = "bad config";
	let r = h.serviceToggle(ctx, { enabled: true });
	assertEq(r.enabled, false);
	assertEq(r.error, "bad config");
});

test("serviceToggle off stops and disables", function() {
	let st = freshState();
	st.global.enabled = "1";
	let r = h.serviceToggle(mockCtx(st), { enabled: false });
	assertEq(r.enabled, false);
	assertEq(st.global.enabled, "0");
	assertEq(st.stopped, true);
});

test("serversPing picks best latency", function() {
	let st = freshState();
	st.fetchResult = { body: SUB, userinfo: "" };
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
