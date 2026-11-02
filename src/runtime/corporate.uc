// Snapshot publication follows the successful nft transaction, never the intention.
import { readfile, rename, unlink, lstat } from 'fs';
import { effective } from '../lib/health.uc';
import { declarations, update } from '../generator/corporate-nft.uc';
import { privateDirectory, atomicPrivate, privateJson, nonce } from './private-store.uc';

const DIR = '/tmp/mb-runtime';
const POLICY = DIR + '/corporate.json';
const SETS = DIR + '/corporate-sets.nft';
function planPolicy(rules, old, health, enabled, now, manual) {
	let out = {};
	for (let rule in rules) {
		let previous = old != null ? old[rule.id] : null;
		let item = effective(rule, previous, health, enabled, now);
		if (item.error != null) return { error: item.error };
		if (manual) {
			item.reset = false;
			item.last_return = previous != null ? previous.last_return : null;
		}
		out[rule.id] = item;
	}
	return { policies: out };
}
function corporateRuntime(sh, io) {
	io = io || { write: atomicPrivate, rename: rename };
	function read() { return privateJson(POLICY, 65536); }
	function install(rules, policies, revision) {
		if (!privateDirectory(DIR)) return 'unsafe_runtime_directory';
		let before = read(), oldSets = readfile(SETS), oldPolicy = readfile(POLICY);
		if (before == null && length(rules)) return 'policy_snapshot_missing';
		let prefix = DIR + '/policy-' + nonce(), error = null, attempted = false, published = false;
		let files = ['.apply', '.rollback', '.sets', '.policy', '.old-sets', '.old-policy'];
		try {
			// Every allocation precedes the kernel transaction. Publication uses rename.
			let staged = io.write(prefix + '.apply', update(rules, policies)) &&
				io.write(prefix + '.rollback', update(before != null ? before.rules || rules : [], before != null ? before.policies : {})) &&
				io.write(prefix + '.sets', declarations(rules, policies)) &&
				io.write(prefix + '.policy', sprintf('%J', { revision: revision, policies: policies, rules: rules })) &&
				(oldSets == null || io.write(prefix + '.old-sets', oldSets)) &&
				(oldPolicy == null || io.write(prefix + '.old-policy', oldPolicy));
			if (!staged) error = 'policy_preparation_failed';
			else {
				attempted = true;
				if (!sh.runCapture('timeout 1 nft -f ' + prefix + '.apply').ok) error = 'nft_update_failed';
				else if (!io.rename(prefix + '.sets', SETS) || !io.rename(prefix + '.policy', POLICY)) error = 'policy_snapshot_failed';
				else published = true;
			}
		} catch (e) { error = 'policy_internal_error'; }
		if (attempted && !published) {
			let restored = false;
			try {
				restored = sh.runCapture('timeout 1 nft -f ' + prefix + '.rollback').ok;
				if (oldSets != null ? !io.rename(prefix + '.old-sets', SETS) : (lstat(SETS) != null && !unlink(SETS))) restored = false;
				if (oldPolicy != null ? !io.rename(prefix + '.old-policy', POLICY) : (lstat(POLICY) != null && !unlink(POLICY))) restored = false;
			} catch (e) { restored = false; }
			if (!restored) { unlink(POLICY); error = 'rollback_failed'; }
		}

		for (let suffix in files) unlink(prefix + suffix);
		return error;
	}

	return { read: read, install: install };
}
export { planPolicy, corporateRuntime, DIR, POLICY, SETS };
