// Чистые rpcd-хендлеры, меняющие состояние: применение конфига, тумблер, режим/правила, geo.
// Чтение (status/servers_list) — в status.uc, подписка — в subscription.uc, выбор сервера — в
// select.uc, замер пинга — в ping.uc. Зависимости (uci/ubus/сеть/файлы) инкапсулированы в `ctx` —
// это держит логику host-тестируемой. Рантайм-привязка ctx — в root/usr/share/rpcd/ucode/monkey-business.uc.
//
// Контракт ctx:
//   getGlobal() -> { enabled, routing_mode, local_region, tproxy_port, custom_direct, custom_proxy, ... }
//   getDns() -> { mode, direct_dns, doh_url }   getAntiDpi() -> { default_fingerprint, xhttp_padding }
//   getSubscriptions() -> [{ ".name", name, url, used_upload, used_download, total, expire, ... }]
//   getSubscription(id) -> subscription|null   setActiveSub(id) -> bool (легло ли в UCI)
//   setSubscriptionUrl(id, url)   setUserinfo(id, { used_upload, used_download, total, expire })
//   getAutoswitch() -> { from, reason }|null   setAutoswitch(from, reason)   clearAutoswitch() (tmpfs)
//   getServers() -> [server, ...]      setServers(arr) -> bool
//   getSelectedServer() -> server|null   getSelectedId() -> string   setSelected(id) — рантайм-состояние,
//     НЕ uci-commit
//   fetchSubscription(url) -> { body, userinfo }|null
//   pingServers([server], limitMs) -> [int(ms)|null] (параллельно, тот же порядок)   now() -> int (epoch, сек)
//   getPings() -> { "<serverId>": { ms } } (tmpfs)   setPings(map)
//   applyConfig(jsonStr, intentOn?) -> errString|null (валидирует + запускает; intentOn=true обходит
//     гейт по enabled в init-скрипте — только для пути включения)   stopService()
//   serviceRunning() -> bool   setEnabled(bool) -> bool (легло ли в UCI)   updateGeo(args) -> { status }
//   failoverCap() -> int (сколько кандидатов пробовать в selectWorking; 0 = все)
//   watchdogPhase() -> "healthy"|"reconnecting"|"down"|null   lastEvent() -> string
//   setCustomRouting(direct, proxy)   setMode(mode, region) -> bool (легло ли в UCI)   warn(msg) -> syslog
//   directBypassActive() -> bool (ФАКТ из nft, не намерение)   geoStatus() -> { state, geoip, geosite, updated }
//   geoInstall(which) -> { ok, detail }   checkExit(domain) -> { ip, country, code }|{ error }
//   hysteriaInstalled() -> bool   applyHysteria(jsonStr|null) -> errString|null

import { applyRouting } from "../lib/routing-transaction.uc";
import { isTrue } from "../lib/val.uc";
import { validateRules } from "../lib/rules.uc";
import { generateJson } from "../generator/xray.uc";
import { selectWorking, listedServers } from "./select.uc";
import { directBypass } from "../lib/bypass.uc";
import { isHysteria } from "../generator/hysteria.uc";
import { prepareHysteria } from "./hysteria.uc";
import { serverId, activeSubId, selectError } from "../lib/subs.uc";

const ROUTING_MODES = ["bypass-local", "gfwlist", "global"];
const LOCAL_REGIONS = ["ru", "cn", "ir", "other"];

function mutate(ctx, fn) {
	return ctx.withMutation != null ? ctx.withMutation(fn) : fn();
}

function genConfig(ctx, server) {
	let g = ctx.getGlobal();
	let bad = map(validateRules(g.custom_direct, g.custom_proxy), function(e) {
		return sprintf("%s line %d (%s)", e.list, e.line, e.code);
	});
	if (length(bad))
		ctx.warn("rpcd: custom rules skipped: " + join(", ", bad));
	return {
		global: g,
		local_addresses: ctx.localAddresses ? ctx.localAddresses() : [],
		corporate_rules: ctx.getCorporateRules ? ctx.getCorporateRules() : [],
		server: server,
		hysteria_credentials: isHysteria(server) && ctx.bridgeCredentials ? ctx.bridgeCredentials(server) : null,
		health: ctx.healthInbound ? ctx.healthInbound() : null,
		dns: ctx.getDns(),
		anti_dpi: ctx.getAntiDpi(),
		test_socks: true,
		dns_transparent: true,
	};
}

// При выключенном VPN рантайм не трогаем вообще: init-скрипт всё равно не поднимет xray (гейт по
// enabled), а без раннего выхода мы бы зря поднимали эфемерный xray на пробу серверов и меняли
// активный сервер. `skipped` нужен UI, чтобы не врать «applied», когда ничего не применялось.
function noServers(ctx, hint) {
	if (length(listedServers(ctx)) > 0)
		return "no usable servers — all are disabled or in expired subscriptions; enable a server or switch the subscription";
	return "no servers — " + hint;
}

function configApply(ctx, args) {
	if (!isTrue(ctx.getGlobal().enabled))
		return { ok: true, skipped: "disabled" };
	let deadline = (args != null) ? int(args.deadline) : 0;
	if (!deadline && ctx.defaultDeadline != null) deadline = ctx.defaultDeadline();
	if (deadline > 0 && ctx.now() >= deadline)
		return { error: "deadline passed before config_apply started" };
	let fence = ctx.runtimeFence != null ? ctx.runtimeFence() : null;
	let sel = selectWorking({ ...ctx, setSelected: function() {} }, deadline > 0 && ctx.applyBudget ? deadline - ctx.applyBudget() : deadline);
	if (sel != null && sel.error != null) return { error: sel.error };
	if (sel == null)
		return { error: noServers(ctx, "add a subscription or a manual server first") };
	return mutate(ctx, function() {
		if (ctx.refresh != null) ctx.refresh();
		if (ctx.runtimeFence != null && ctx.runtimeFence() != fence) return { error: 'runtime_conflict' };
		if (!isTrue(ctx.getGlobal().enabled)) return { error: 'intent_conflict' };
		if (ctx.currentCandidate != null && !ctx.currentCandidate(sel.server)) return { error: 'candidate_conflict' };
		let hErr = prepareHysteria(ctx, sel.server);
		if (hErr != null) return { error: hErr };
		let applied = genConfig(ctx, sel.server);
		let jsonStr = generateJson(applied);
		let err = ctx.applyConfig(jsonStr, false, applied);
		if (err != null) return { error: err };
		ctx.setSelected(serverId(sel.server));
		return { ok: true, server: sel.server.tag, server_id: serverId(sel.server), probed: sel.probed,
			bytes: length(jsonStr), runtime_fence: ctx.recoveryFence ? ctx.recoveryFence() : null };
	});
}

function serviceToggle(ctx, args) {
	let on = (args != null) && isTrue(args.enabled);
	if (!on) return mutate(ctx, function() {
		if (ctx.refresh != null) ctx.refresh();
		if (!ctx.setEnabled(false)) return { error: 'intent_save_failed' };
		if (ctx.stopService() === false) return { enabled: false, error: 'stop_failed' };
		return { enabled: false };
	});
	let fence = ctx.runtimeFence != null ? ctx.runtimeFence() : null;
	let sel = selectWorking({ ...ctx, setSelected: function() {} }, ctx.defaultDeadline ? ctx.defaultDeadline() - ctx.applyBudget() : 0);
	if (sel != null && sel.error != null) return { error: sel.error };
	if (sel == null)
		return { error: noServers(ctx, "add a subscription first"), enabled: false };
	return mutate(ctx, function() {
		if (ctx.refresh != null) ctx.refresh();
		if (ctx.runtimeFence != null && ctx.runtimeFence() != fence) return { error: 'runtime_conflict' };
		if (ctx.currentCandidate != null && !ctx.currentCandidate(sel.server)) return { error: 'candidate_conflict' };
		let hErr = prepareHysteria(ctx, sel.server);
		if (hErr != null) return { error: hErr, enabled: isTrue(ctx.getGlobal().enabled) };
		let applied = genConfig(ctx, sel.server);
		let err = ctx.applyConfig(generateJson(applied), true, applied);
		if (err != null) return { error: err, enabled: isTrue(ctx.getGlobal().enabled) };
		if (!ctx.setEnabled(true)) {
			ctx.stopService();
			return { error: "could not save the toggle state (read-only config?)", enabled: false };
		}
		ctx.setSelected(serverId(sel.server));
		return { enabled: true, server: sel.server.tag, server_id: serverId(sel.server), probed: sel.probed };
	});
}

function geoUpdate(ctx, args) {
	return ctx.updateGeo(args);
}

// Режим маршрутизации + регион переехали из формы Settings на дашборд: они меняют не только конфиг
// xray, но и файрвол (ядерный обход), а форма LuCI умеет только стейджить UCI — «сохранил и ничего
// не изменилось» здесь особенно дорого. Пишем и применяем сразу, как setRouting (src/rpcd/routing.uc). Пустое значение =
// «не трогать»: UI шлёт оба поля, но ubus-контракт допускает частичный вызов.
function setMode(ctx, args) {
	if (ctx.routingSnapshot != null) {
		let snapshot = ctx.routingSnapshot();
		if (snapshot.error != null) return { error: snapshot.error };
		let candidate = snapshot.candidate;
		if (args != null && args.mode != null && args.mode != '') candidate.mode = args.mode;
		if (args != null && args.region != null && args.region != '') candidate.region = args.region;
		return applyRouting(ctx, { expected_revision: snapshot.revision,
			request_id: 'legacy_' + ctx.randomHex() + ctx.randomHex(), candidate: candidate });
	}

	let g = ctx.getGlobal();
	let prevMode = g.routing_mode || "bypass-local";
	let prevRegion = g.local_region || "ru";
	let mode = (args != null && args.mode != null && args.mode != "") ? args.mode : prevMode;
	let region = (args != null && args.region != null && args.region != "") ? args.region : prevRegion;
	// Значения идут в конфиг xray как имена geo-категорий (geoip:<region>): мусор отсюда — это
	// `xray -test` на каждом apply, то есть отказ применять ЛЮБЫЕ настройки до ручной правки UCI.
	if (index(ROUTING_MODES, mode) < 0)
		return { error: "bad routing mode" };
	if (index(LOCAL_REGIONS, region) < 0)
		return { error: "bad local region" };
	if (!ctx.setMode(mode, region))
		return { error: "could not save the routing mode (read-only config?)" };
	let res = configApply(ctx);
	// Пара уже в UCI, а xray.json перегенерируется ТОЛЬКО успешным apply — при этом ядерный обход
	// init-скрипт считает из UCI. Провал оставил бы файрвол по новой паре, а туннель по старому
	// конфигу, и расхождение пережило бы ребут (start_service конфиг не пересобирает). Не
	// применилось — откатываем пару, чтобы оба источника остались на прежнем согласованном наборе.
	if (res.error != null) {
		ctx.setMode(prevMode, prevRegion);
		return res;
	}
	res.mode = mode;
	res.region = region;
	res.direct_bypass = directBypass(ctx.getGlobal());
	return res;
}

function subscriptionSelect(ctx, args) {
	let want = (args != null) ? args.sub : null;
	let subs = ctx.getSubscriptions();
	let err = selectError(subs, want, ctx.now());
	if (err != null)
		return { error: err };
	let prev = ctx.getGlobal().active_sub || "";
	if (activeSubId(subs, prev) == want) {
		ctx.clearAutoswitch();
		return { ok: true, active_sub: want, unchanged: true };
	}
	let prevId = ctx.getSelectedId();
	if (!ctx.setActiveSub(want))
		return { error: "could not save the subscription choice (read-only config?)" };
	let res = configApply(ctx);
	if (res.error != null) {
		if (ctx.getGlobal().active_sub == want) ctx.setActiveSub(prev);
		// A failed installation never changed the applied snapshot or selected ID.
		return res;
	}
	ctx.clearAutoswitch();
	res.active_sub = want;
	return res;
}

function geoStatus(ctx) {
	return ctx.geoStatus();
}

function geoInstall(ctx, args) {
	let which = (args != null) ? args.which : null;
	if (which != "geoip" && which != "geosite")
		return { error: "bad which (geoip|geosite)" };
	return ctx.geoInstall(which);
}

// Проверка сплита: запрос к гео-сервису через тестовый SOCKS-inbound -> по каким правилам ушёл
// (proxy/direct), какой выходной IP/страна. domain = гео-сервис (по умолчанию ip-api.com).
function checkExit(ctx, args) {
	let domain = (args != null) ? args.domain : null;
	return ctx.checkExit(domain);
}

export { genConfig, configApply, serviceToggle, geoUpdate, setMode, subscriptionSelect, geoStatus, geoInstall,
	checkExit };
