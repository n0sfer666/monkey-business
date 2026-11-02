// rpcd ucode-плагин monkey-business (РАНТАЙМ, device-side).
// Регистрирует ubus-объект 'monkey-business' и делегирует логику чистым хендлерам.
// Сам файл — только проводка: контракт ctx собирается из модулей runtime/*.
//
// ВЕРИФИКАЦИЯ: только на устройстве/в dev-VM (нужны модули uci/fs + uclient-fetch +
// init.d + xray). Чистая логика покрыта host-тестами (test/unit/rpcd_test.uc).
//
// Установка (см. packaging): src/* -> /usr/share/rpcd/ucode/lib/monkey-business/*
'use strict';

import * as uci from 'uci';
import { readfile, stat } from 'fs';
// АБСОЛЮТНЫЙ путь: rpcd-mod-ucode компилирует плагин из буфера (без пути к файлу),
// поэтому относительный import не резолвится. Транзитивные импорты в lib/ грузятся из
// файла и остаются относительными. Путь = место установки (см. шапку и deploy/packaging).
import * as h from '/usr/share/rpcd/ucode/lib/monkey-business/rpcd/handlers.uc';
import { atomicPrivate, privateJson, nonce } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/private-store.uc';
import { fingerprint } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/fingerprint.uc';
import { outboundPayload } from '/usr/share/rpcd/ucode/lib/monkey-business/lib/outbound.uc';
import { acquireMutation } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/mutation.uc';
import { loadApplied } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/applied.uc';
import { serverRef, resolveRef } from '/usr/share/rpcd/ucode/lib/monkey-business/lib/availability.uc';
import { localAddresses } from '/usr/share/rpcd/ucode/lib/monkey-business/lib/local-addresses.uc';
import * as hrouting from '/usr/share/rpcd/ucode/lib/monkey-business/rpcd/routing-v2.uc';
import { routingRuntime } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/routing-v2.uc';
import { privateDirectory } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/private-store.uc';
import { readRouting } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/routing-uci.uc';
import * as hstatus from '/usr/share/rpcd/ucode/lib/monkey-business/rpcd/status.uc';
import * as hsub from '/usr/share/rpcd/ucode/lib/monkey-business/rpcd/subscription.uc';
import { publicHealth, networkEpoch } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/health-context.uc';
import { listenerOwner } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/engine-listener.uc';
import { availabilityCache } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/availability-cache.uc';
import { serverOrder, writePriority } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/server-order.uc';
import { shortProbe } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/short-probe.uc';
import { availabilitySettings } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/availability-settings.uc';
import { availabilityApi } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/availability-api.uc';
import * as hswitch from '/usr/share/rpcd/ucode/lib/monkey-business/rpcd/autoswitch.uc';
import * as huri from '/usr/share/rpcd/ucode/lib/monkey-business/rpcd/uri.uc';
import * as hy from '/usr/share/rpcd/ucode/lib/monkey-business/rpcd/hysteria.uc';
import { serverConnect } from '/usr/share/rpcd/ucode/lib/monkey-business/rpcd/connect.uc';
import { routingCheck, setRouting } from '/usr/share/rpcd/ucode/lib/monkey-business/rpcd/routing.uc';
import * as sh from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/shell.uc';
import { CONFIG, XRAY_CONF } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/paths.uc';
import { loadSection, loadSubscriptions, loadServers, storeServers, replaceServers, selectedId, selectedServer, storeSelected }
	from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/uci.uc';
import { findSub } from '/usr/share/rpcd/ucode/lib/monkey-business/lib/subs.uc';
import { loadPings, storePings } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/pings.uc';
import { loadAutoswitch, storeAutoswitch, clearAutoswitch }
	from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/autoswitch.uc';
import { netRuntime } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/net.uc';
import { applyRuntime } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/apply.uc';
import { hysteriaRuntime } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/hysteria.uc';

const hysteria = hysteriaRuntime(sh.runCapture);
const net = netRuntime(sh, hysteria, stat);
const app = applyRuntime(sh);

function freshCursor() {
	if (!privateDirectory('/tmp/mb-runtime') || !privateDirectory('/tmp/mb-runtime/uci') || !privateDirectory('/tmp/mb-runtime/uploads'))
		die('unsafe_runtime_directory');
	return uci.cursor('/etc/config', '/tmp/mb-runtime/uci');
}
function buildCtx() {
	let cursor = freshCursor(), mutationHeld = false;
	let pendingBridge = null;
	let bridgeCredentials = { user: nonce(), pass: nonce() };
	let healthCredentials = { user: nonce(), pass: nonce() };
	let ctx;
	ctx = {
		bridgeCredentials: function(server) {
			let previous = loadApplied();
			if (previous != null && previous.config.hysteria_credentials != null &&
				sprintf('%J', [serverRef(previous.config.server), outboundPayload(previous.config.server)]) ==
				sprintf('%J', [serverRef(server), outboundPayload(server)])) return previous.config.hysteria_credentials;
			return bridgeCredentials;
		},
		healthInbound: function() { return { port: 11800, credentials: healthCredentials }; },
		refresh: function() { cursor.unload(CONFIG); cursor.load(CONFIG); },
		runtimeFence: function() {
			let current = freshCursor(), applied = loadApplied();
			return fingerprint([applied != null ? [applied.generation, applied.epoch] : 'missing',
				current.get(CONFIG, 'global', 'enabled'), current.get(CONFIG, 'global', 'active_sub'),
				map(loadServers(current), function(server) { return [serverRef(server), outboundPayload(server), server.disabled]; }), privateJson('/tmp/mb-runtime/intent.json', 4096),
				networkEpoch(), loadSection(current, 'availability')]);
		},
		withMutation: function(fn) {
			if (mutationHeld) return fn();
			let lock = acquireMutation();
			if (lock == null) return { error: 'busy' };
			let result; mutationHeld = true;
			try { result = fn(); } catch (e) { result = { error: 'mutation_failed' }; }
			mutationHeld = false; lock.close();
			return result;
		},
		currentCandidate: function(server) {
			let found = resolveRef(loadServers(freshCursor()), serverRef(server));
			return found.error == null && sprintf('%J', [serverRef(found.server), outboundPayload(found.server), found.server.disabled]) ==
				sprintf('%J', [serverRef(server), outboundPayload(server), server.disabled]);
		},
		getGlobal: function() { return loadSection(cursor, 'global'); },
		getCorporateRules: function() { let r = readRouting(freshCursor()); if (r.error != null) die(r.error); return r.candidate.corporate_rules; },
		getDns: function() { return loadSection(cursor, 'dns'); },
		getAntiDpi: function() { return loadSection(cursor, 'anti_dpi'); },
		getSubscriptions: function() { return loadSubscriptions(cursor); },
		getSubscription: function(id) { return findSub(loadSubscriptions(cursor), id); },
		setActiveSub: function(id) {
			let result = ctx.withMutation(function() {
				let fresh = freshCursor(); fresh.set(CONFIG, 'global', 'active_sub', id);
				return { ok: fresh.commit(CONFIG) === true };
			});
			ctx.refresh(); return result.ok === true;
		},
		getServers: function() { return loadServers(cursor); },
		setPriority: function(servers, activeSub) {
			let error = writePriority(freshCursor(), servers, activeSub);
			cursor.unload(CONFIG); cursor.load(CONFIG);
			return error == null;
		},
		setServers: function(servers) {
			let result = ctx.withMutation(function() { return { ok: storeServers(freshCursor(), servers) }; });
			ctx.refresh(); return result.ok === true;
		},
		storeSubscription: function(id, url, servers, userinfo) {
			replaceServers(cursor, servers); cursor.set(CONFIG, id, 'url', url);
			if (userinfo != null) for (let key in ['used_upload', 'used_download', 'total', 'expire']) cursor.set(CONFIG, id, key, userinfo[key] || '');
			return cursor.commit(CONFIG) === true;
		},
		getSelectedServer: function() { let applied = loadApplied(); return applied != null ? applied.config.server : selectedServer(cursor); },
		getSelectedId: function() { return selectedId(); },
		setSelected: function(id) { storeSelected(sh, id); },
		setSubscriptionUrl: function(id, url) {
			cursor.set(CONFIG, id, 'url', url);
			cursor.commit(CONFIG);
		},
		addSubscription: function(id, name, url) {
			let result = ctx.withMutation(function() {
			let cursor = freshCursor();
			if (cursor.get(CONFIG, id) != null) return { ok: false };
			cursor.set(CONFIG, id, 'subscription');
			cursor.set(CONFIG, id, 'name', name);
			cursor.set(CONFIG, id, 'url', url);
			cursor.set(CONFIG, id, 'auto_update', '1');
			cursor.set(CONFIG, id, 'update_interval', '3600');
			return { ok: cursor.commit(CONFIG) === true };
			}); ctx.refresh(); return result.ok === true;
		},
		removeSubscription: function(id, expectedUrl) {
			let result = ctx.withMutation(function() {
				let fresh = freshCursor();
				if ((fresh.get(CONFIG, id, 'url') || '') != (expectedUrl || '')) return { ok: false };
				fresh.delete(CONFIG, id); return { ok: fresh.commit(CONFIG) === true };
			}); ctx.refresh(); return result.ok === true;
		},
		randomHex: function() {
			let raw = readfile('/dev/urandom', 4) || '';
			let out = '';
			for (let i = 0; i < length(raw); i++)
				out += sprintf('%02x', ord(raw, i));
			return out;
		},
		setUserinfo: function(id, o) {
			cursor.set(CONFIG, id, 'used_upload', o.used_upload || '');
			cursor.set(CONFIG, id, 'used_download', o.used_download || '');
			cursor.set(CONFIG, id, 'total', o.total || '');
			cursor.set(CONFIG, id, 'expire', o.expire || '');
			cursor.commit(CONFIG);
		},
		getAutoswitch: function() { return loadAutoswitch(); },
		setAutoswitch: function(from, reason) { storeAutoswitch(from, reason); },
		clearAutoswitch: function() { clearAutoswitch(); },
		fetchSubscription: function(url) { return net.fetchSubscription(url); },
		getPings: function() { return {}; },
		availabilityRecords: function() { return availabilityCache(loadServers(freshCursor()), availabilitySettings(freshCursor).get()); },
		healthStatus: function() { return publicHealth(freshCursor); },
		setPings: function(pings) { storePings(pings); },
		now: function() { return time(); },
		probeServer: function(s) {
			let method = availabilitySettings(freshCursor).get();
			return method.error == null && shortProbe(sh, loadSection(cursor, 'dns'), s, method.targets);
		},
		// Каждая проба — до ~10с. Без потолка 7 серверов = ~70с, что дольше ubus-таймаута:
		// вызов рвался, watchdog читал это как «рабочих серверов нет» и уходил в down,
		// хотя rpcd на той стороне доходил до конца и переключался.
		// 0/не задано = перебирать ВЕСЬ список. Жёсткий дефолт вроде 3 при 7 серверах делал
		// рабочий сервер на 4-й позиции недостижимым ни для watchdog, ни для «Turn on».
		defaultDeadline: function() { return time() + 65; },
		applyBudget: function() { return 30; },
		failoverCap: function() {
			let v = int(cursor.get(CONFIG, 'global', 'failover_cap') || 0);
			return (v > 0) ? v : 0;
		},
		watchdogPhase: function() { let r = privateJson('/tmp/mb-runtime/recovery.json', 4096); return r != null ? r.phase : null; },
		// Тег mb-event, а не monkey-business: последним под общим тегом почти всегда оказывалась
		// служебная строка apply.sh/flush.sh («tproxy firewall flushed») из init.d, а не причина
		// отказа — а в фазе down init.d дёргается каждый тик.
		lastEvent: function() {
			let r = sh.runCapture('logread -e mb-event 2>/dev/null | tail -n 1');
			return sh.firstLine(sh.stripExit(r.out));
		},
		applyConfig: function(jsonStr, intentOn, applied) { return app.applyConfig(jsonStr, intentOn, applied, null, pendingBridge); },
		stopService: function() { return sh.runCapture('MB_APPLYING=1 timeout 20 /etc/init.d/monkey-business stop >/dev/null 2>&1').ok; },
		recoveryFence: function() {
			let a = loadApplied(); return a != null ? sprintf('%J', [a.generation, a.epoch, privateJson('/tmp/mb-runtime/intent.json', 4096)]) : null;
		},
		serviceRunning: function() {
			return listenerOwner('/sys/fs/cgroup/monkey-business-engines/live', 11800) != null &&
				(stat('/etc/monkey-business/hysteria.json') == null || listenerOwner('/sys/fs/cgroup/monkey-business-engines/live', 10810) != null);
		},
		// Возврат = легло ли намерение в UCI: на read-only rootfs commit не проходит, а туннель к
		// этому моменту уже поднят обходом гейта — вызывающий обязан узнать и свернуть его.
		setEnabled: function(on) {
			if (!atomicPrivate('/tmp/mb-runtime/intent.json', sprintf('%J', { epoch: nonce() }))) return false;
			cursor.set(CONFIG, 'global', 'enabled', on ? '1' : '0');
			return cursor.commit(CONFIG) === true;
		},
		checkExit: function(domain) { return net.checkExit(domain); },
		// Возврат = легло ли в UCI: файрвол (init.d) читает пару из UCI, а не из памяти курсора, и
		// незаписанный на read-only rootfs режим дал бы «применили» при неизменившемся обходе.
		setMode: function(mode, region) {
			cursor.set(CONFIG, 'global', 'routing_mode', mode);
			cursor.set(CONFIG, 'global', 'local_region', region);
			return cursor.commit(CONFIG) === true;
		},
		// Обход ФАКТИЧЕСКИ включён = в prerouting стоит правило по сету mb_ru4 (его ставит apply.sh
		// только при MB_DIRECT_BYPASS=1). Читаем цепочку, а не сет: в mb_ru4 тысячи RU-CIDR, а
		// status опрашивается раз в 5с. Нет таблицы (VPN выключен) — nft молчит в stderr, и это
		// честный false.
		directBypassActive: function() {
			return index(sh.runCapture('nft list chain inet monkey_business prerouting 2>/dev/null').out,
				'mb_ru4') >= 0;
		},
		hysteriaInstalled: function() { return hysteria.installed(); },
		applyHysteria: function(jsonStr) { pendingBridge = { json: jsonStr }; return null; },
		hysteriaStatus: function() { return hysteria.status(); },
		hysteriaInstall: function() { return hysteria.install(); },
		warn: function(msg) { system('logger -t monkey-business ' + sh.shq(msg)); },
		setCustomRouting: function(direct, proxy) {
			cursor.set(CONFIG, 'global', 'custom_direct', direct);
			cursor.set(CONFIG, 'global', 'custom_proxy', proxy);
			cursor.commit(CONFIG);
		},
		updateGeo: function(args) {
			let result = ctx.withMutation(function() {
				let fresh = freshCursor();
				if (args != null && (args.geoip_url != null || args.geosite_url != null)) {
					fresh.set(CONFIG, 'geo', 'geoip_url', args.geoip_url || '');
					fresh.set(CONFIG, 'geo', 'geosite_url', args.geosite_url || '');
					if (!fresh.commit(CONFIG)) return { error: 'geo_settings_commit_failed' };
				}
				return { ok: true };
			});
			return result.error != null ? result : app.updateGeo();
		},
		geoStatus: function() { return app.geoStatus(); },
		geoInstall: function(which) { return app.geoInstall(which); },
	};
	return { ...ctx, ...routingRuntime(sh, freshCursor, app, ctx.serviceRunning) };
}

const availability = availabilityApi(freshCursor);
function deprecatedPing() { return { api_version: 2, error: 'deprecated', replacement: 'availability_start' }; }
const orders = serverOrder(freshCursor);
const methods = {
	servers_order_get: { call: function() { return orders.get(); } },
	servers_order_apply: { args: { expected_revision: '', request_id: '', groups: [] }, call: function(req) { return orders.apply(req.args); } },
	availability_start: { args: { scope: '', sub: '', server_ref: {} }, call: function(req) { return availability.start(req.args); } },
	availability_status: { args: { job_id: '', offset: 0, limit: 50 }, call: function(req) { return availability.status(req.args); } },
	availability_cancel: { args: { job_id: '' }, call: function(req) { return availability.cancel(req.args); } },
	availability_settings_get: { call: function() { return availability.settingsGet(); } },
	availability_settings_apply: { args: { expected_revision: '', targets: [] }, call: function(req) { return availability.settingsApply(req.args); } },
	routing_get: { call: function() { return hrouting.routingGet(buildCtx()); } },
	routing_validate: { args: { candidate: {} }, call: function(req) { return hrouting.routingValidate({ localAddresses: function() { let fib = readfile('/proc/net/fib_trie'); if (fib == null) die('interface_query_failed'); return localAddresses(fib); } }, req.args); } },
	routing_apply: { args: { expected_revision: '', request_id: '', candidate: {} }, call: function(req) { return hrouting.routingApply(buildCtx(), req.args); } },
	status:               { call: function() { return hstatus.status(buildCtx()); } },
	servers_list:         { call: function() { return hstatus.serversList(buildCtx()); } },
	servers_ping:         { call: function() { return deprecatedPing(); } },
	subscription_ping:    { args: { sub: '' }, call: function(req) { return deprecatedPing(); } },
	server_ping:          { args: { id: '' }, call: function(req) { return deprecatedPing(); } },
	subscription_update:  { args: { url: '', sub: '' }, call: function(req) { return hsub.subscriptionUpdate(buildCtx(), req.args); } },
	subscription_add:     { args: { name: '', url: '' }, call: function(req) { return hsub.subscriptionAdd(buildCtx(), req.args); } },
	subscription_autoswitch: { args: { check: false, deadline: 0 }, call: function(req) { return hswitch.subscriptionAutoswitch(buildCtx(), req.args); } },
	subscription_select:  { args: { sub: '' }, call: function(req) { return h.subscriptionSelect(buildCtx(), req.args); } },
	parse_uri:            { args: { uri: '', section: '' }, call: function(req) { return huri.parseServerUri(buildCtx(), req.args); } },
	server_link:          { args: { section: '' }, call: function(req) { return huri.serverLink(buildCtx(), req.args); } },
	server_connect:       { args: { id: '', server_ref: {} }, call: function(req) { return serverConnect(buildCtx(), req.args); } },
	config_apply:         { args: { deadline: 0 }, call: function(req) { return h.configApply(buildCtx(), req.args); } },
	service_toggle:       { args: { enabled: false }, call: function(req) { return h.serviceToggle(buildCtx(), req.args); } },
	geo_update:           { args: { geoip_url: '', geosite_url: '' }, call: function(req) { return h.geoUpdate(buildCtx(), req.args); } },
	set_routing:          { args: { direct: '', proxy: '' }, call: function(req) { return setRouting(buildCtx(), req.args); } },
	routing_check:        { args: { direct: '', proxy: '' }, call: function(req) { return routingCheck(req.args); } },
	set_mode:             { args: { mode: '', region: '' }, call: function(req) { return h.setMode(buildCtx(), req.args); } },
	geo_status:           { call: function() { return h.geoStatus(buildCtx()); } },
	geo_install:          { args: { which: '' }, call: function(req) { return h.geoInstall(buildCtx(), req.args); } },
	check_exit:           { args: { domain: '' }, call: function(req) { return h.checkExit(buildCtx(), req.args); } },
	hysteria_status:      { call: function() { return hy.hysteriaStatus(buildCtx()); } },
	hysteria_install:     { call: function() { return hy.hysteriaInstall(buildCtx()); } },
};

return { 'monkey-business': methods };
