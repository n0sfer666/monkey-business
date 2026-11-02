import { beginTransition, endTransition, scope } from './corporate-transition.uc';
import { readfile, unlink, lstat } from 'fs';
import { readRouting, writeRouting, withRouting } from './routing-uci.uc';
import { loadApplied, storeApplied } from './applied.uc';
import { fingerprint } from './fingerprint.uc';
import { acquireMutation } from './mutation.uc';
import { privateDirectory, privateJson, atomicPrivate, nonce } from './private-store.uc';
import { planPolicy, corporateRuntime, DIR, SETS, POLICY } from './corporate.uc';
import { readHealth, healthContext } from './health-context.uc';
import { initial } from '../lib/health.uc';
import { declarations } from '../generator/corporate-nft.uc';
import { generateJson } from '../generator/xray.uc';
import { isHysteria, hysteriaConfigJson } from '../generator/hysteria.uc';
import { localAddresses as parseAddresses } from '../lib/local-addresses.uc';
import { isTrue } from '../lib/val.uc';

function monotonic() { return +split(readfile('/proc/uptime') || '0', ' ')[0]; }
function routingRuntime(sh, freshCursor, app, running) {
	let lock = null;
	let corporate = corporateRuntime(sh);
	function localAddresses() {
		let fib = readfile('/proc/net/fib_trie');
		if (fib == null) die('interface_query_failed');
		return parseAddresses(fib);
	}
	function snapshot() {
		let cursor = freshCursor();
		let stored = readRouting(cursor);
		if (stored.error != null) return stored;
		let applied = loadApplied();
		let policy = corporate.read();
		if (applied != null && isTrue(cursor.get('monkey-business', 'global', 'enabled')) && length(applied.config.corporate_rules || []) && policy == null) return { error: 'policy_snapshot_missing' };
		return { candidate: stored.candidate, revision: fingerprint(stored.candidate),
			generation: applied != null ? applied.generation : 'missing',
			runtime: fingerprint(healthContext(freshCursor)),
			intent: privateJson(DIR + '/intent.json', 4096),
			enabled: isTrue(cursor.get('monkey-business', 'global', 'enabled')),
			outbound: applied, health: readHealth(freshCursor),
			policies: policy != null ? policy.policies : {},
			runtime_error: privateJson(DIR + '/routing-error.json', 4096) || (privateJson(DIR + '/corporate-transition.json', 262144) != null ? { error: 'transition_pending' } : null) };
	}
	function requestCache() {
		let cached = privateJson(DIR + '/routing-requests.json', 4194304);
		return type(cached) == 'array' ? filter(cached, function(item) {
			return monotonic() >= item.created && monotonic() - item.created < 600;
		}) : [];
	}
	function requestResult(id) {
		for (let item in requestCache()) if (item.id == id) {
			let error = privateJson(DIR + '/routing-error.json', 4096);
			if (item.result.ok && error != null && error.error == 'rollback_failed') return { ...item, result: { error: 'rollback_failed' } };
			if (item.result.ok && privateJson(DIR + '/corporate-transition.json', 262144) != null) return { ...item, result: { error: 'busy' } };
			return item;
		}
		return null;
	}
	function prepare(candidate, before) {
		if (!privateDirectory(DIR)) return { error: 'unsafe_runtime_directory' };
		let result = { prefix: DIR + '/routing-' + nonce(), candidate: candidate };
		try {
		if (!before.enabled) return result;
		result.config = withRouting(before.outbound.config, candidate);
		result.config.local_addresses = localAddresses();
		let h = before.health;
		if (h == null || h.context == null || h.context.outbound != before.generation)
			h = initial({ boot: trim(readfile('/proc/sys/kernel/random/boot_id')), outbound: before.generation,
				runtime: 'preparing', method: 'pending', network: 'pending' });
		let planned = planPolicy(candidate.corporate_rules, before.policies, h, true, monotonic(), true);
		if (planned.error != null) return { ...result, error: planned.error };
		result.policies = planned.policies;
		if (!atomicPrivate(result.prefix + '.json', generateJson(result.config)) ||
			!atomicPrivate(result.prefix + '.nft', 'table inet mb_validate {' +
				declarations(candidate.corporate_rules, planned.policies) + '\n}\ndelete table inet mb_validate\n'))
			return { ...result, error: 'preparation_write_failed' };
		if (!sh.runCapture('timeout 10 xray run -test -c ' + result.prefix + '.json >/dev/null 2>&1').ok)
			return { ...result, error: 'xray_validation_failed' };
		if (!sh.runCapture('timeout 5 nft -c -f ' + result.prefix + '.nft >/dev/null 2>&1').ok)
			return { ...result, error: 'nft_validation_failed' };
		return result;
		} catch (e) { return { ...result, error: 'preparation_failed' }; }
	}
	function discard(prepared) {
		if (prepared.prefix == null) return;
		unlink(prepared.prefix + '.json'); unlink(prepared.prefix + '.nft');
	}
	function install(prepared, before) {
		if (!atomicPrivate(DIR + '/routing-journal.json', sprintf('%J', { before: before,
			candidate: prepared.candidate }))) return 'journal_write_failed';
		if (!before.enabled) return null;
		let barrier = beginTransition(sh, [scope(before.outbound.config, before.policies), scope(prepared.config, prepared.policies)]);
		if (barrier != null) return barrier;
		if (!atomicPrivate(SETS, declarations(prepared.candidate.corporate_rules, prepared.policies)))
			return 'policy_write_failed';
		return app.applyConfig(readfile(prepared.prefix + '.json'), false, null, prepared.candidate, { json: isHysteria(prepared.config.server) ? hysteriaConfigJson(prepared.config.server, { credentials: prepared.config.hysteria_credentials }) : null }, prepared.config.global, true);
	}
	function restore(before) {
		if (before.enabled && before.outbound != null) {
			let current = loadApplied(), policy = corporate.read();
			let guard = beginTransition(sh, [scope(before.outbound.config, before.policies),
				scope(current != null ? current.config : before.outbound.config, policy != null ? policy.policies : before.policies)]);
			if (guard != null) return guard;
		}
		let err = writeRouting(freshCursor(), before.candidate);
		if (before.enabled && before.outbound != null) {
			if (!atomicPrivate(SETS, declarations(before.candidate.corporate_rules, before.policies)))
				err = 'restore_policy_failed';
			let runtime = app.applyConfig(generateJson(before.outbound.config), false, null, before.candidate, { json: isHysteria(before.outbound.config.server) ? hysteriaConfigJson(before.outbound.config.server, { credentials: before.outbound.config.hysteria_credentials }) : null }, before.outbound.config.global, true);
			if (runtime != null) err = runtime;
			if (!storeApplied(before.outbound.config, before.generation)) err = 'restore_snapshot_failed';
		}
		if (!atomicPrivate(POLICY, sprintf('%J', { revision: before.revision, policies: before.policies, rules: before.candidate.corporate_rules }))) err = 'restore_policy_snapshot_failed';
		if (err != null) atomicPrivate(DIR + '/routing-error.json', '{"error":"rollback_failed"}');
		else unlink(DIR + '/routing-journal.json');
		return err;
	}
	return {
		requestBody: fingerprint, localAddresses: localAddresses, routingSnapshot: snapshot, requestResult: requestResult,
		prepareRouting: prepare, discardRouting: discard,
		lockMutation: function() { lock = acquireMutation(); return lock != null; },
		unlockMutation: function() { if (lock != null) lock.close(); lock = null; },
		installRouting: install,
		verifyRouting: function(prepared, before) {
			if (!before.enabled) return null;
			return running() ? null : 'runtime_not_running';
		},
		commitRouting: function(candidate) { return writeRouting(freshCursor(), candidate); },
		publishRouting: function(prepared, before) {
			if (before.enabled && !storeApplied(prepared.config, before.generation)) return 'snapshot_write_failed';
			let err = before.enabled ? corporate.install(prepared.candidate.corporate_rules,
				prepared.policies, fingerprint(prepared.candidate)) : null;
			if (err != null) return err;
			unlink(DIR + '/routing-journal.json'); unlink(DIR + '/routing-error.json');
			return null;
		},
		restoreRouting: restore,
		finishRouting: function(before) {
			let error = before.enabled ? endTransition(sh) : null;
			if (error != null) atomicPrivate(DIR + '/routing-error.json', '{"error":"rollback_failed","cause":"transition_release_failed"}');
			else if (lstat(DIR + '/routing-error.json') != null && !unlink(DIR + '/routing-error.json')) error = 'error_cleanup_failed';
			return error;
		},
		recordRequest: function(id, body, result) {
			let cached = filter(requestCache(), function(item) { return item.id != id; });
			if (length(cached) >= 16) shift(cached);
			push(cached, { id: id, body: body, result: result, created: monotonic() });
			if (!atomicPrivate(DIR + '/routing-requests.json', sprintf('%J', cached))) die('request_cache_failed');
		},
	};
}
export { routingRuntime, monotonic };
