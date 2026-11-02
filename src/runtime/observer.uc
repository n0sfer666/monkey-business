// The only active-VPN observer. Probes run outside the shared mutation lock.
import { readfile, lsdir, unlink, rmdir } from 'fs';
import * as socket from 'socket';
import { initial, round, sameContext } from '../lib/health.uc';
import { healthContext } from './health-context.uc';
import { fingerprint } from './fingerprint.uc';
import { privateDirectory, privateJson, atomicPrivate, nonce } from './private-store.uc';
import { acquireMutation } from './mutation.uc';
import { spawnOwned, finished, collect, stopOwned } from './owned-process.uc';
import { acquireSlots, releaseSlots } from './probe-slots.uc';
import { corporateRuntime, planPolicy } from './corporate.uc';
import { monotonic } from './routing-v2.uc';
import { resetReturnedFlows } from './corporate-conntrack.uc';
const ROOT = '/tmp/mb-runtime';
function observer(sh, freshCursor) {
	let corporate = corporateRuntime(sh);
	function snapshot() { return healthContext(freshCursor); }
	function tick() {
		let lock = acquireMutation();
		if (lock == null) return;
		let before = snapshot();
		if (before == null || !before.enabled) { unlink(ROOT + '/health.json'); lock.close(); return; }
		lock.close();
		let previous = privateJson(ROOT + '/health.json', 65536);
		if (previous == null || !sameContext(previous.context, before.context)) previous = initial(before.context);
		let sample = { https: 'unknown', udp: 'unknown' }, child = null, slots = null;
		let directory = ROOT + '/observer/' + nonce(), started = monotonic(), reset = null;
		if (before.missing) sample = { https: 'failure', udp: 'failure', reason: 'live_engine_missing' };
		else if (privateDirectory(ROOT + '/observer') && privateDirectory(directory)) {
			try {
				slots = acquireSlots('observer', true);
				if (slots == null) die('slots_busy');
				let diagnostic = { ...before.live, ...before.applied.config.health };
				if (!atomicPrivate(directory + '/request.json', sprintf('%J', { diagnostic: diagnostic, targets: before.method.targets }))) die('write_failed');
				child = spawnOwned(['ucode', '/usr/share/monkey-business/health-round.uc', directory + '/request.json'], directory, 10);
				if (child.error != null) die('spawn_failed');
				while (!finished(child) && monotonic() - started < 11) socket.poll(20);
				if (finished(child)) {
					let result = collect(child);
					if (result.error == null && result.code == 0) sample = json(result.output);
				}
			} catch (e) { sample = { https: 'unknown', udp: 'unknown', reason: 'observer_method_error' }; }
			if (child != null && child.handle != null) stopOwned(child);
			if (slots != null) releaseSlots(slots);
			for (let file in (lsdir(directory) || [])) unlink(directory + '/' + file);
			rmdir(directory);
		}
		if (monotonic() - started >= 12 || type(sample) != 'object') sample = { https: 'unknown', udp: 'unknown', reason: 'round_deadline' };
		lock = acquireMutation();
		if (lock == null) return;
		try {
			let after = snapshot();
			if (after != null && after.enabled && sameContext(before.context, after.context)) {
				let next = round(previous, before.context, sample.https, sample.udp, monotonic());
				next.partial = sample.partial; next.udp_partial = sample.udp_partial; next.reason = sample.reason;
				let rules = before.applied.config.corporate_rules || [], old = corporate.read();
				let planned = planPolicy(rules, old != null ? old.policies : {}, next, true, monotonic(), false);
				let revision = fingerprint(rules);
				if (planned.error == null) {
					let error = corporate.install(rules, planned.policies, revision);
					if (error == null) {
						next.conntrack = privateJson(ROOT + '/conntrack.json', 4096) || { state: 'not_needed' };
						if (next.conntrack.state == 'pending') next.conntrack = { state: 'failed', reason: 'reset_result_unknown' };
						for (let rule in rules) if (planned.policies[rule.id].reset) reset = { rules: rules, policies: planned.policies, revision: revision };
						if (reset != null) {
							next.conntrack = { state: 'pending', boot: before.context.boot, outbound: before.context.outbound, started: monotonic() };
							if (!atomicPrivate(ROOT + '/conntrack.json', sprintf('%J', next.conntrack))) { next.conntrack = { state: 'failed', reason: 'reset_claim_failed' }; reset = null; }
						}
					} else next.policy_error = error;
				}
				atomicPrivate(ROOT + '/health.json', sprintf('%J', next));
			}
		} catch (e) { /* A failed method never changes an installed kernel policy. */ }
		lock.close();
		if (reset != null) {
			let outcome;
			try {
				outcome = resetReturnedFlows(sh, reset.rules, reset.policies, before.applied.config.global.lan_iface || 'br-lan', {
					deadline: min(started + 11.5, monotonic() + 1.5),
					execute: function(command) {
						let guard = acquireMutation();
						if (guard == null) return { obsolete: true };
						let result = { obsolete: true };
						try {
							let current = snapshot(), installed = corporate.read();
							if (current != null && current.enabled && sameContext(current.context, before.context) &&
								installed != null && installed.revision == reset.revision && sprintf('%J', installed.policies) == sprintf('%J', reset.policies))
								result = sh.runCapture(command);
						} catch (e) {}
						guard.close(); return result;
					}
				});
			} catch (e) { outcome = { state: 'failed', reason: 'conntrack_method_error' }; }
			lock = acquireMutation();
			if (lock != null) {
				let current = snapshot();
				if (current != null && current.enabled && sameContext(current.context, before.context)) {
					let health = privateJson(ROOT + '/health.json', 65536);
					if (health != null && sameContext(health.context, before.context)) {
						health.conntrack = { ...outcome, boot: before.context.boot, outbound: before.context.outbound };
						atomicPrivate(ROOT + '/conntrack.json', sprintf('%J', health.conntrack));
						atomicPrivate(ROOT + '/health.json', sprintf('%J', health));
					}
				}
				lock.close();
			}
		}
	}
	return { tick: tick, snapshot: snapshot };
}
export { observer };
