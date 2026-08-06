import { test, assert, assertEq, run } from "../harness.uc";
import * as h from "../../src/rpcd/handlers.uc";
import { readfile } from "fs";

const SUB = readfile("test/fixtures/sub_urilist.txt");
const SUB_HOPS = readfile("test/fixtures/sub_hop_dupes.txt");
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
		probeServer: function(s) { return (state.probeFail == null) || (state.probeFail[s.tag] !== true); },
		failoverCap: function() { return state.failoverCap || 0; },
		// enabledAtApply + applyIntent пинят ПОРЯДОК: туннель поднимается ДО commit'а тумблера, а
		// гейт по enabled в init-скрипте обходится явным intentOn (MB_INTENT=1) — только на пути
		// включения. Обратный порядок держал enabled=1 всю пробу серверов, и cron-watchdog успевал
		// поднять старый конфиг.
		applyConfig: function(j, intentOn) {
			state.applied = j;
			state.applyIntent = intentOn;
			state.enabledAtApply = state.global.enabled;
			return state.applyErr;
		},
		setCustomRouting: function(d, p) { state.custom = { direct: d, proxy: p }; },
		setMode: function(mode, region) {
			if (state.setModeFail)
				return false;
			state.global.routing_mode = mode;
			state.global.local_region = region;
			return true;
		},
		stopService: function() { state.stopped = true; },
		serviceRunning: function() { return state.running; },
		setEnabled: function(b) {
			if (state.setEnabledFail)
				return false;
			state.global.enabled = b ? "1" : "0";
			return true;
		},
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
	assertEq(r.local_region, "ru");
	assertEq(r.direct_bypass, true);
	assertEq(r.traffic.used_download, "20");
	assertEq(r.traffic.total, "300");
});

// Без фазы watchdog UI не мог отличить «поднимается» от «watchdog сдался и LAN идёт мимо VPN»
// и вечно показывал «Starting…».
test("status exposes watchdog phase and last event", function() {
	let st = freshState();
	let ctx = mockCtx(st);
	ctx.watchdogPhase = function() { return "down"; };
	ctx.lastEvent = function() { return "VPN stopped, LAN on direct."; };
	let r = h.status(ctx);
	assertEq(r.wd_phase, "down");
	assertEq(r.last_event, "VPN stopped, LAN on direct.");
});

test("status stays valid when ctx has no watchdog hooks (older runtime)", function() {
	let r = h.status(mockCtx(freshState()));
	assertEq(r.wd_phase, null);
	assertEq(r.last_event, "");
});

// В healthy плашки с событием в UI нет, а status опрашивается раз в 5с — lastEvent() дампит
// syslog, и звать его на каждом опросе значит жечь CPU роутера впустую.
test("status skips lastEvent while healthy", function() {
	let calls = 0;
	let ctx = mockCtx(freshState());
	ctx.watchdogPhase = function() { return "healthy"; };
	ctx.lastEvent = function() { calls++; return "should not be read"; };
	let r = h.status(ctx);
	assertEq(r.wd_phase, "healthy");
	assertEq(r.last_event, "");
	assertEq(calls, 0);
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

test("subscriptionUpdate keeps distinct servers, collapses exact dupes (5-vs-7 fix)", function() {
	let st = freshState();
	st.fetchResult = { body: SUB_HOPS, userinfo: "" };
	let ctx = mockCtx(st);
	h.subscriptionUpdate(ctx, {});
	// 5 ссылок: 🛡️NL/🛡️FR (один hop, отличие только tag), 🚀NL/🚀FR (разные порты), дубль 🛡️NL.
	// serverKey = идентичность подключения + tag -> 4 уникальных, точный дубль 🛡️NL схлопнут.
	assertEq(length(st.servers), 4);
	let hop = 0, tds = 0;
	for (let s in st.servers) {
		if (s.address == "hop.example.com") hop++;
		if (s.address == "tds.example.com") tds++;
	}
	// hop==2: два байт-идентичных 🛡️ (NL/FR) различены по tag, но точный дубль 🛡️NL схлопнут
	// (без tag в ключе было бы 1; без дедупа дубля — 3). tds==2: 🚀 различены по порту.
	assertEq(hop, 2);
	assertEq(tds, 2);
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

test("selectBest picks first by order (priority), ignoring ping", function() {
	let st = freshState();
	st.servers = [
		{ tag: "A", address: "a", port: 1 },
		{ tag: "B", address: "b", port: 2 },
		{ tag: "C", address: "c", port: 3 },
	];
	st.pings = { "A": null, "B": 50, "C": 20 };
	let chosen = h.selectBest(mockCtx(st));
	assertEq(chosen.tag, "A");
	assertEq(st.selected, "A");
});

test("selectBest returns null when no servers", function() {
	let st = freshState();
	assert(h.selectBest(mockCtx(st)) == null, "null on empty");
});

test("configApply auto-selects and passes dns+anti_dpi", function() {
	let st = freshState();
	st.global.enabled = "1";
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
	// НЕ путь включения: обход гейта (intentOn) здесь запрещён, иначе config_apply снова поднимал бы
	// туннель при выключенном тумблере — ровно тот баг, из-за которого гейт и появился
	assert(!st.applyIntent, "config_apply does not bypass the enabled gate");
});

test("configApply re-selects first server by order (reorder switches active)", function() {
	let st = freshState();
	st.global.enabled = "1";
	st.fetchResult = { body: SUB, userinfo: "" };
	let ctx = mockCtx(st);
	h.subscriptionUpdate(ctx, {});
	// эмулируем drag: второй сервер становится первым
	st.servers = [ st.servers[1], st.servers[0] ];
	st.selected = st.servers[1].tag;   // активен пока старый первый
	st.pings = {};                      // никто не пингуется -> fallback на первый по порядку
	h.configApply(ctx);
	assertEq(st.selected, st.servers[0].tag);
});

test("configApply errors with no servers", function() {
	let st = freshState();
	st.global.enabled = "1";
	let r = h.configApply(mockCtx(st));
	assert(index(r.error, "no servers") >= 0, "no-servers error");
});

test("configApply surfaces apply/validation error", function() {
	let st = freshState();
	st.global.enabled = "1";
	st.fetchResult = { body: SUB, userinfo: "" };
	let ctx = mockCtx(st);
	h.subscriptionUpdate(ctx, {});
	st.applyErr = "xray: invalid config";
	let r = h.configApply(ctx);
	assertEq(r.error, "xray: invalid config");
});

test("configApply fails over past unreachable server to next working", function() {
	let st = freshState();
	st.global.enabled = "1";
	st.fetchResult = { body: SUB, userinfo: "" };
	let ctx = mockCtx(st);
	h.subscriptionUpdate(ctx, {});
	// первый по приоритету не проходит пробу -> failover на второй (имя-агностично)
	st.probeFail = {};
	st.probeFail[st.servers[0].tag] = true;
	let r = h.configApply(ctx);
	assertEq(r.probed, true);
	assertEq(r.server, st.servers[1].tag);
	assertEq(st.selected, st.servers[1].tag);
	assert(index(st.applied, st.servers[1].address) >= 0, "applied uses second server");
});

test("configApply falls back to top when all probes fail (kill-switch preserved)", function() {
	let st = freshState();
	st.global.enabled = "1";
	st.fetchResult = { body: SUB, userinfo: "" };
	let ctx = mockCtx(st);
	h.subscriptionUpdate(ctx, {});
	st.probeFail = {};
	for (let s in st.servers)
		st.probeFail[s.tag] = true;
	let r = h.configApply(ctx);
	assertEq(r.probed, false);
	assertEq(r.server, st.servers[0].tag);
	assert(index(st.applied, st.servers[0].address) >= 0, "applied uses top server as fallback");
});

// Сохранение настроек при выключенном VPN не должно ни поднимать туннель, ни трогать активный
// сервер, ни врать UI словом «applied»: enabled — источник истины для рантайма.
test("configApply skips runtime work while disabled", function() {
	let st = freshState();
	st.fetchResult = { body: SUB, userinfo: "" };
	let ctx = mockCtx(st);
	h.subscriptionUpdate(ctx, {});
	let before = st.selected;
	st.global.enabled = "0";
	let r = h.configApply(ctx);
	assertEq(r.skipped, "disabled");
	assert(r.error == null, "not an error — настройки сохранены");
	assertEq(st.applied, null);
	assertEq(st.selected, before);
});

// Списки маршрутизации обязаны лечь в UCI даже при выключенном VPN — гейт стоит ПОСЛЕ записи,
// иначе правки молча терялись бы, а при включении применился бы старый сплит.
test("setRouting persists lists while disabled", function() {
	let st = freshState();
	let r = h.setRouting(mockCtx(st), { direct: "a.example", proxy: "b.example" });
	assertEq(r.skipped, "disabled");
	assertEq(st.custom.direct, "a.example");
	assertEq(st.custom.proxy, "b.example");
});

// Ядерный обход перестал быть отдельным тумблером: единственный источник истины — режим. Иначе
// оставалась пара, в которой xray гонит регион в туннель, а ядро в это же время уводит RU-CIDR
// мимо него — трафик идёт открытым в режиме, где пользователь этого не просил.
test("directBypass follows the routing mode and the region", function() {
	assertEq(h.directBypass({ routing_mode: "bypass-local", local_region: "ru" }), true);
	assertEq(h.directBypass({ routing_mode: "bypass-local", local_region: "cn" }), false);
	assertEq(h.directBypass({ routing_mode: "bypass-local", local_region: "other" }), false);
	assertEq(h.directBypass({ routing_mode: "gfwlist", local_region: "ru" }), false);
	assertEq(h.directBypass({ routing_mode: "global", local_region: "ru" }), false);
	// пустая секция = дефолты конфига (bypass-local + ru); пустая строка = то же самое, что
	// отсутствие ключа — иначе расчёт разъехался бы с mb_direct_bypass() в init-скрипте
	assertEq(h.directBypass({}), true);
	assertEq(h.directBypass({ routing_mode: "", local_region: "" }), true);
	assertEq(h.directBypass({ routing_mode: "", local_region: "cn" }), false);
});

test("setMode commits the pair, applies it and reports the derived bypass", function() {
	let st = freshState();
	st.global.enabled = "1";
	st.fetchResult = { body: SUB, userinfo: "" };
	let ctx = mockCtx(st);
	h.subscriptionUpdate(ctx, {});
	st.applied = null;
	let r = h.setMode(ctx, { mode: "gfwlist", region: "ru" });
	assertEq(st.global.routing_mode, "gfwlist");
	assertEq(st.global.local_region, "ru");
	assertEq(r.direct_bypass, false);
	assert(st.applied != null, "config re-applied");
	assert(index(st.applied, "geolocation-!ru") >= 0, "new mode is in the applied config");
});

// Мусор отсюда попадает в конфиг именем geo-категории (geoip:<region>) -> `xray -test` валится,
// и роутер перестаёт применять ЛЮБЫЕ настройки до ручной правки UCI.
test("setMode rejects unknown values without touching the config", function() {
	let st = freshState();
	let ctx = mockCtx(st);
	assert(index(h.setMode(ctx, { mode: "everything", region: "ru" }).error, "bad routing mode") >= 0, "mode validated");
	assert(index(h.setMode(ctx, { mode: "global", region: "geoip:ru" }).error, "bad local region") >= 0, "region validated");
	assertEq(st.global.routing_mode, "bypass-local");
	assertEq(st.global.local_region, "ru");
});

test("setMode keeps the current value for an omitted field", function() {
	let st = freshState();
	let r = h.setMode(mockCtx(st), { mode: "global" });
	assertEq(st.global.routing_mode, "global");
	assertEq(st.global.local_region, "ru");
	assertEq(r.skipped, "disabled");
});

// Провал apply оставлял бы файрвол по новой паре (init.d считает обход из UCI), а туннель — по
// старому конфигу: xray.json перегенерируется только успешным apply, и расхождение пережило бы
// ребут. Пара обязана откатиться.
test("setMode rolls the pair back when the apply fails", function() {
	let st = freshState();
	st.global.enabled = "1";
	st.fetchResult = { body: SUB, userinfo: "" };
	let ctx = mockCtx(st);
	h.subscriptionUpdate(ctx, {});
	st.applyErr = "xray: invalid config";
	let r = h.setMode(ctx, { mode: "global", region: "cn" });
	assert(index(r.error, "invalid config") >= 0, "error is reported");
	assertEq(st.global.routing_mode, "bypass-local");
	assertEq(st.global.local_region, "ru");
});

// Незаписанная пара (read-only rootfs) — это «применили» при неизменившемся файрволе: init.d читает
// UCI, а не память курсора.
test("setMode reports a failed commit instead of applying", function() {
	let st = freshState();
	st.global.enabled = "1";
	st.setModeFail = true;
	let ctx = mockCtx(st);
	let r = h.setMode(ctx, { mode: "global", region: "ru" });
	assert(index(r.error, "could not save") >= 0, "commit failure surfaces");
	assertEq(st.applied, null);
	assertEq(st.global.routing_mode, "bypass-local");
});

// Индикатор обхода — индикатор утечки: он показывает ФАКТ из nft, а не намерение из UCI (пара могла
// разойтись с применённым файрволом — правка uci руками, провал apply, выключенный VPN).
test("status prefers the applied bypass over the configured one", function() {
	let st = freshState();
	let ctx = mockCtx(st);
	ctx.directBypassActive = function() { return false; };
	assertEq(h.status(ctx).direct_bypass, false);
	ctx.directBypassActive = function() { return true; };
	st.global.routing_mode = "global";
	assertEq(h.status(ctx).direct_bypass, true);
});

// Дефолтный cap=0 обязан значить «весь список»: жёсткий потолок делал рабочий сервер в хвосте
// недостижимым ни для watchdog, ни для «Turn on».
test("selectWorking with default cap probes every server", function() {
	let st = freshState();
	st.fetchResult = { body: SUB, userinfo: "" };
	let ctx = mockCtx(st);
	h.subscriptionUpdate(ctx, {});
	let last = st.servers[length(st.servers) - 1];
	st.probeFail = {};
	for (let s in st.servers)
		st.probeFail[s.tag] = (s.tag != last.tag);
	let r = h.selectWorking(ctx);
	assertEq(r.probed, true);
	assertEq(r.server.tag, last.tag);
});

test("selectWorking honours an explicit cap", function() {
	let st = freshState();
	st.fetchResult = { body: SUB, userinfo: "" };
	let ctx = mockCtx(st);
	h.subscriptionUpdate(ctx, {});
	st.failoverCap = 1;
	st.probeFail = {};
	st.probeFail[st.servers[0].tag] = true;
	let r = h.selectWorking(ctx);
	assertEq(r.probed, false);
	assertEq(r.server.tag, st.servers[0].tag);
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
	// тумблер коммитится ПОСЛЕ применения, а гейт обходится intentOn — иначе enabled=1 висел бы всё
	// время пробы серверов и watchdog поднял бы старый конфиг в это окно
	assertEq(st.enabledAtApply, "0");
	assertEq(st.applyIntent, true);
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
	// тумблер не включился: применение провалилось, а enabled=1 без туннеля заставил бы watchdog
	// «лечить» сервис, которого нет, и дашборд показывал бы «on»
	assertEq(st.global.enabled, "0");
});

// Намерение не легло в UCI (read-only rootfs): туннель уже поднят обходом гейта, оставлять его
// нельзя — за таким xray+kill-switch никто не следит, а дашборд показывает «off».
test("serviceToggle on tears down the tunnel if intent cannot be saved", function() {
	let st = freshState();
	st.fetchResult = { body: SUB, userinfo: "" };
	let ctx = mockCtx(st);
	h.subscriptionUpdate(ctx, {});
	st.setEnabledFail = true;
	let r = h.serviceToggle(ctx, { enabled: true });
	assertEq(r.enabled, false);
	assert(index(r.error, "could not save") >= 0, "honest error");
	assertEq(st.stopped, true);
	assertEq(st.global.enabled, "0");
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
