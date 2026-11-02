// Boot uses committed routing plus the last applied outbound, never a new subscription.
import { engineIdentities, listenerOwner } from './engine-listener.uc';
import { beginTransition, endTransition, scope } from './corporate-transition.uc';
import { localAddresses } from '../lib/local-addresses.uc';
import { APPLIED } from './applied.uc';
import { readfile, unlink, lstat } from 'fs';
import { loadApplied, storeApplied } from './applied.uc';
import { readRouting, withRouting } from './routing-uci.uc';
import { atomicPrivate, privateDirectory, privateJson, nonce } from './private-store.uc';
import { acquireMutation } from './mutation.uc';
import { XRAY_CONF } from './paths.uc';
import { DIR, SETS, POLICY, planPolicy } from './corporate.uc';
import { initial } from '../lib/health.uc';
import { fingerprint } from './fingerprint.uc';
import { declarations } from '../generator/corporate-nft.uc';
import { generateJson } from '../generator/xray.uc';
import { hysteriaConfigJson, isHysteria } from '../generator/hysteria.uc';

function reconcile(sh, cursor, inherited) {
	let lock = inherited ? null : acquireMutation();
	if (!inherited && lock == null) return 'busy';
	let error = null, guardInstalled = false, priorGuard = privateJson(DIR + '/corporate-transition.json', 262144) != null;
	function guard(scopes) { let result = beginTransition(sh, scopes); guardInstalled = result == null; return result; }
	let files = [XRAY_CONF, '/etc/monkey-business/hysteria.json', APPLIED, SETS, POLICY], before = {};
	for (let path in files) before[path] = readfile(path);
	let tmp = DIR + '/reconcile-' + nonce() + '.json';
	try {
		let applied = loadApplied();
		let routing = readRouting(cursor);
		if (applied == null) error = 'applied_outbound_missing';
		else if (routing.error != null) error = routing.error;
		else {
			let config = withRouting(applied.config, routing.candidate);
			config.local_addresses = localAddresses(readfile('/proc/net/fib_trie'));
			let generated = generateJson(config);
			let boot = trim(readfile('/proc/sys/kernel/random/boot_id'));
			let policy = privateJson(POLICY, 65536);
			let oldPolicies = policy != null ? policy.policies : {}, prior = {};
			if (policy == null) for (let rule in applied.config.corporate_rules || []) oldPolicies[rule.id] = { route: 'proxy' };
			for (let rule in config.corporate_rules || [])
				for (let old in applied.config.corporate_rules || [])
					if (sprintf('%J', [old.id, old.address, old.port, old.enabled, old.requires_udp]) ==
						sprintf('%J', [rule.id, rule.address, rule.port, rule.enabled, rule.requires_udp])) prior[rule.id] = oldPolicies[rule.id];
			let health = initial({ boot: boot, outbound: applied.generation, runtime: applied.epoch || 'reconcile', method: 'reconcile', network: 'reconcile' });
			let planned = planPolicy(config.corporate_rules || [], prior, health, true, +split(readfile('/proc/uptime'), ' ')[0], true);
			if (planned.error != null) die('reconcile_policy_failed');
			if (!privateDirectory(DIR) || !atomicPrivate(tmp, generated)) error = 'reconcile_write_failed';
			else if (!sh.runCapture('timeout 10 xray run -test -c ' + tmp + ' >/dev/null 2>&1').ok)
				error = 'reconcile_validation_failed';
			else if (guard([scope(applied.config, oldPolicies), scope(config, planned.policies)]) != null) error = 'reconcile_guard_failed';
			else if (!atomicPrivate(DIR + '/startup.json', sprintf('%J', { before: before, old_config: applied.config,
				old_kernel: sh.runCapture('timeout 1 nft list table inet monkey_business >/dev/null 2>&1').ok,
				old_owner: listenerOwner('/sys/fs/cgroup/monkey-business-engines/live', 11800),
				blocked: engineIdentities('/sys/fs/cgroup/monkey-business-engines/live'), changed_xray: before[XRAY_CONF] != generated,
				changed_bridge: before['/etc/monkey-business/hysteria.json'] != (isHysteria(config.server) ? hysteriaConfigJson(config.server, { credentials: config.hysteria_credentials }) : null), wants_bridge: isHysteria(config.server) }))) error = 'reconcile_journal_failed';
			else if (!atomicPrivate(SETS, declarations(routing.candidate.corporate_rules, planned.policies)))
				error = 'reconcile_policy_failed';
			else if (readfile(XRAY_CONF) != generated && !atomicPrivate(XRAY_CONF, generated))
				error = 'reconcile_install_failed';
			else {
				let hy = '/etc/monkey-business/hysteria.json';
				if (isHysteria(config.server)) {
					if (!atomicPrivate(hy, hysteriaConfigJson(config.server, { credentials: config.hysteria_credentials }))) error = 'reconcile_hysteria_failed';
				} else unlink(hy);
				if (error == null && !storeApplied(config, applied.generation)) error = 'reconcile_snapshot_failed';
				if (error == null && !atomicPrivate(POLICY, sprintf('%J', { revision: fingerprint(routing.candidate), policies: planned.policies, rules: config.corporate_rules || [] }))) error = 'reconcile_policy_snapshot_failed';
			}
		}
		if (error == null) unlink(DIR + '/routing-journal.json');
	} catch (e) { error = 'reconcile_failed'; }
	if (error != null) {
		let restored = true;
		for (let path in files) {
			if (before[path] == null) { if (lstat(path) != null && !unlink(path)) restored = false; } else if (!atomicPrivate(path, before[path])) restored = false;
		}
		if (restored && (!guardInstalled || priorGuard || endTransition(sh) == null)) { if (!priorGuard) unlink(DIR + '/startup.json'); }
		else error = 'rollback_failed';
		atomicPrivate(DIR + '/routing-error.json', sprintf('%J', { error: error }));
	}
	unlink(tmp);
	if (lock != null) lock.close();
	return error;
}
export { reconcile };
