// Установка сгенерированного конфига на живой xray: валидация, атомарная подмена файла, reload.
// Здесь же geo — конфиг без geo-баз xray не примет, и отказ должен быть внятным, а не «bad config».

import { beginTransition, endTransition, scope } from './corporate-transition.uc';
import { readfile, stat, unlink } from 'fs';
import * as socket from 'socket';
import { listenerOwner, engineIdentities, acceptedOwner } from './engine-listener.uc';

import { atomicPrivate, privateJson, nonce } from './private-store.uc';
import { declarations } from '../generator/corporate-nft.uc';
import { privateDirectory } from './private-store.uc';
import { DIR, SETS, POLICY, planPolicy } from './corporate.uc';
import { directBypass } from '../lib/bypass.uc';
import { isTrueByDefault } from '../lib/val.uc';
import { outboundPayload } from '../lib/outbound.uc';
import { serverRef } from '../lib/availability.uc';
import { initial } from '../lib/health.uc';
import { APPLIED, loadApplied, storeApplied } from './applied.uc';
import { CONF_DIR, XRAY_CONF, GEO_DIR, GEO_SCRIPT } from './paths.uc';

// Размер, а не только наличие: оборванная закачка оставляет .dat в пару килобайт — проверка
// на null проходит, а xray потом падает на старте с невнятной ошибкой парсинга гео-базы.
function geoPresent() {
	let ip = stat(GEO_DIR + '/geoip.dat'), site = stat(GEO_DIR + '/geosite.dat');
	return ip != null && site != null && ip.size > 0 && site.size > 0;
}

function applyRuntime(sh) {
	// Валидирует конфиг реальным xray, при успехе устанавливает + поднимает сервис.
	// Возврат: строка-ошибка | null(успех).
	//
	// Установка атомарная: пишем в соседний .tmp на ТОМ ЖЕ разделе, валидируем именно тот файл,
	// что ляжет на место (а не /tmp-копию), и только потом rename. Раньше обрыв на writefile
	// оставлял обрезанный xray.json, а `restart` всё равно звался -> сервис не поднимался.
	// intentOn=true: reload идёт с MB_INTENT=1 — init-скрипт поднимается, не глядя на ещё не
	// выставленный тумблер. Нужен только пути включения (service_toggle); остальные вызовы обязаны
	// упираться в гейт, иначе config_apply при выключенном VPN снова поднимал бы туннель молча.
	function applyConfig(jsonStr, intentOn, applied, routing, bridge, runtimeGlobal, transitionHeld) {
		let token = nonce();
		let predecessor = loadApplied();
		let g = applied != null ? applied.global : runtimeGlobal || (predecessor != null ? predecessor.config.global : {});
		function globals(value) {
			return 'MB_APPLIED_LAN_IFACE=' + sh.shq(value.lan_iface || 'br-lan') +
				' MB_APPLIED_TPROXY_PORT=' + int(value.tproxy_port || 12345) +
				' MB_APPLIED_KILL_SWITCH=' + (isTrueByDefault(value.kill_switch) ? '1' : '0') + ' ';
		}
		let overrides = globals(g) + 'MB_APPLYING=1 MB_KEEP_FIREWALL=1 MB_APPLY_TOKEN=' + token + ' ';
		routing = routing || { mode: g.routing_mode || 'bypass-local', region: g.local_region || 'ru', proxy: g.custom_proxy || '' };
		if (routing != null) overrides += 'MB_ROUTING_MODE=' + sh.shq(routing.mode) +
			' MB_LOCAL_REGION=' + sh.shq(routing.region) + ' MB_FORCE_PROXY=' + sh.shq(routing.proxy) + ' ';
		function firewall(global, scope) {
			let env = 'MB_LAN_IFACE=' + sh.shq(global.lan_iface || 'br-lan') +
				' MB_TPROXY_PORT=' + int(global.tproxy_port || 12345) +
				' MB_KILL_SWITCH=' + (isTrueByDefault(global.kill_switch) ? '1' : '0') +
				' MB_DIRECT_BYPASS=' + (directBypass({ routing_mode: scope.mode, local_region: scope.region }) ? '1' : '0') +
				' MB_FORCE_PROXY=' + sh.shq(scope.proxy || '') + ' ';
			return sh.runCapture(env + 'timeout 5 sh /usr/share/monkey-business/firewall/apply.sh >/dev/null 2>&1').ok &&
				atomicPrivate(DIR + '/firewall-applied', token);
		}
		let reload = overrides + (intentOn ? 'MB_INTENT=1 ' : '') +
			'timeout 20 /etc/init.d/monkey-business reload >/dev/null 2>&1';
		system('mkdir -p ' + CONF_DIR);
		if (!geoPresent()) return 'geo databases missing — press "Update geo databases" on the Dashboard first';
		if (!privateDirectory(DIR)) return 'unsafe_runtime_directory';
		let tmp = CONF_DIR + '/.xray.new.json';
		if (!atomicPrivate(tmp, jsonStr)) return 'failed to write config (disk full?)';
		let validation = sh.runCapture('timeout 10 xray run -test -c ' + tmp + ' 2>&1');
		if (!validation.ok) { unlink(tmp); return 'xray config validation failed'; }
		let hy = CONF_DIR + '/hysteria.json';
		let before = {};
		let liveGroup = '/sys/fs/cgroup/monkey-business-engines/live';
		let verify = applied != null ? applied.health != null : runtimeGlobal != null;
		let oldProcesses = verify ? engineIdentities(liveGroup) : [];
		let oldOwner = verify ? listenerOwner(liveGroup, 11800) : null;
		let oldBridge = verify ? listenerOwner(liveGroup, 10810) : null;
		let tablePresent = verify ? sh.runCapture('timeout 1 nft list table inet monkey_business >/dev/null 2>&1').ok : true;
		let wasOff = (intentOn && !isTrueByDefault(applied != null ? applied.global.enabled : null)) || (verify && oldOwner == null && !tablePresent);
		function ready(changedXray, changedBridge, wantsBridge, blocked, allowedXray, allowedBridge) {
			if (!verify) return true;
			let until = +split(readfile('/proc/uptime'), ' ')[0] + 5;
			while (+split(readfile('/proc/uptime'), ' ')[0] < until) {
				let x = listenerOwner(liveGroup, 11800), h = listenerOwner(liveGroup, 10810);
				let xChanged = !changedXray || acceptedOwner(x, blocked, allowedXray);
				let hChanged = !changedBridge || acceptedOwner(h, blocked, allowedBridge);
				if (x != null && xChanged && (wantsBridge ? h != null && hChanged : h == null)) return true;
				socket.poll(20);
			}
			return false;
		}
		for (let path in [XRAY_CONF, hy, APPLIED, SETS, POLICY]) before[path] = readfile(path);
		let changed = applied != null && (intentOn || predecessor == null || readfile(POLICY) == null ||
			sprintf('%J', [serverRef(applied.server), outboundPayload(applied.server), applied.dns, applied.anti_dpi, applied.hysteria_credentials]) !=
			sprintf('%J', [serverRef(predecessor.config.server), outboundPayload(predecessor.config.server), predecessor.config.dns, predecessor.config.anti_dpi, predecessor.config.hysteria_credentials]));
		let priorPolicy = privateJson(POLICY, 65536);
		let oldConfig = predecessor != null ? predecessor.config : { global: g, corporate_rules: [] };
		let oldPolicies = priorPolicy != null ? priorPolicy.policies : {};
		if (priorPolicy == null) for (let rule in oldConfig.corporate_rules || []) oldPolicies[rule.id] = { route: 'proxy' };
		let seedPolicies = oldPolicies;
		if (applied != null) {
			let retained = {};
			if (!changed) for (let rule in applied.corporate_rules || [])
				for (let old in oldConfig.corporate_rules || [])
					if (sprintf('%J', old) == sprintf('%J', rule)) retained[rule.id] = oldPolicies[rule.id];
			let boot = trim(readfile('/proc/sys/kernel/random/boot_id'));
			seedPolicies = planPolicy(applied.corporate_rules || [], retained,
				initial({ boot: boot, outbound: predecessor != null && !changed ? predecessor.generation : 'changing',
					runtime: 'pending', method: 'pending', network: 'pending' }), true, 0, true).policies;
		}
		let guardOwned = !transitionHeld;
		let guardScopes = [scope(oldConfig, oldPolicies), scope(applied != null ? applied : oldConfig, seedPolicies)];
		if (guardOwned) {
			let barrier = beginTransition(sh, guardScopes);
			if (barrier != null) { unlink(tmp); return barrier; }
		}
		let error = null;
		// Install the bridge together with Xray, after offline validation. A rejected
		// VLESS candidate must never remove the still-applied Hysteria bridge.
		if (bridge != null) {
			if (bridge.json == null) { if (stat(hy) != null && !unlink(hy)) error = 'bridge_remove_failed'; }
			else if (readfile(hy) != bridge.json && !atomicPrivate(hy, bridge.json)) error = 'bridge_write_failed';
		}
		if (error == null && applied != null &&
			!atomicPrivate(SETS, declarations(applied.corporate_rules || [], seedPolicies))) error = 'corporate_boot_policy_failed';
		if (error == null && readfile(XRAY_CONF) != jsonStr && !atomicPrivate(XRAY_CONF, jsonStr))
			error = 'config_install_failed';
		unlink(tmp);
		if (error == null && !sh.runCapture(reload).ok)
			error = 'runtime_reload_failed';
		if (error == null && !ready(before[XRAY_CONF] != jsonStr, before[hy] != readfile(hy), stat(hy) != null, oldProcesses, null, null)) error = 'runtime_not_ready';
		if (error == null && !firewall(g, routing)) error = 'runtime_firewall_failed';
		if (error == null && applied != null && !storeApplied(applied, changed ? null : predecessor.generation)) error = 'applied_snapshot_write_failed';
		if (error == null && applied != null) {
			let recorded = loadApplied();
			for (let id in seedPolicies) {
				seedPolicies[id].boot = recorded.boot; seedPolicies[id].outbound = recorded.generation;
			}
			if (!atomicPrivate(POLICY, sprintf('%J', { policies: seedPolicies, rules: applied.corporate_rules || [] }))) error = 'policy_snapshot_failed';
		}
		if (error == null && guardOwned) error = endTransition(sh);

		if (error != null) {
			let restored = true;
			if (guardOwned && beginTransition(sh, guardScopes) != null) return 'rollback_failed';
			let rollbackProcesses = verify ? engineIdentities(liveGroup) : [];
			let installedBridge = readfile(hy);
			for (let path in [XRAY_CONF, hy, APPLIED, SETS, POLICY]) {
				if (before[path] == null) { if (stat(path) != null && !unlink(path)) restored = false; }
				else if (!atomicPrivate(path, before[path])) restored = false;
			}
			// No working predecessor exists on first activation. Do not report recovery
			// of an outbound that never ran.
			if (wasOff) {
				if (!sh.runCapture('MB_APPLYING=1 timeout 20 /etc/init.d/monkey-business stop >/dev/null 2>&1').ok) restored = false;
			} else if (before[XRAY_CONF] == null) restored = false;
			else {
				let previousRouting = predecessor != null ? predecessor.config.global : null;
				let restoreReload = globals(previousRouting || {}) + 'MB_APPLYING=1 MB_KEEP_FIREWALL=1 MB_APPLY_TOKEN=' + token + ' ' + (intentOn ? 'MB_INTENT=1 ' : '');
				if (previousRouting != null) restoreReload += 'MB_ROUTING_MODE=' + sh.shq(previousRouting.routing_mode || 'bypass-local') +
					' MB_LOCAL_REGION=' + sh.shq(previousRouting.local_region || 'ru') + ' MB_FORCE_PROXY=' + sh.shq(previousRouting.custom_proxy || '') + ' ';
				restoreReload += 'timeout 20 /etc/init.d/monkey-business reload >/dev/null 2>&1';
				if (!sh.runCapture(restoreReload).ok ||
					!ready(before[XRAY_CONF] != jsonStr, before[hy] != installedBridge, before[hy] != null,
					rollbackProcesses, oldOwner, oldBridge) ||
					!firewall(previousRouting || g, { mode: previousRouting != null ? previousRouting.routing_mode || 'bypass-local' : routing.mode,
						region: previousRouting != null ? previousRouting.local_region || 'ru' : routing.region,
						proxy: previousRouting != null ? previousRouting.custom_proxy || '' : routing.proxy })) restored = false;
			}
			if (restored && guardOwned && endTransition(sh) != null) restored = false;
			return restored ? error : 'rollback_failed';
		}
		unlink(DIR + '/routing-error.json');
		return null;
	}

	function updateGeo() {
		// фон: скачивание ~29MB дольше ubus-таймаута (30s). UI поллит geo_status.
		if (!privateDirectory(DIR)) return { error: 'unsafe_runtime_directory' };
		system('umask 077; sh ' + GEO_SCRIPT + ' download >' + DIR + '/geo.log 2>&1 &');
		return { status: 'started' };
	}

	function geoStatus() {
		let line = sh.firstLine(sh.stripExit(sh.runCapture('sh ' + GEO_SCRIPT + ' status').out));
		let j = (line != '') ? json(line) : null;
		return (type(j) == 'object') ? j : { state: 'idle', geoip: 0, geosite: 0 };
	}

	function geoInstall(which) {
		// defense-in-depth: whitelist и здесь (which идёт в команду + имя файла)
		if (which != "geoip" && which != "geosite")
			return { ok: false, detail: "bad which" };
		let r = sh.runCapture('sh ' + GEO_SCRIPT + ' install ' + which + ' /tmp/mb-runtime/uploads/' + which + '.dat 2>&1');
		return { ok: r.ok, detail: sh.firstLine(sh.stripExit(r.out)) };
	}

	return {
		applyConfig: applyConfig,
		updateGeo: updateGeo,
		geoStatus: geoStatus,
		geoInstall: geoInstall,
	};
}

export { applyRuntime };
