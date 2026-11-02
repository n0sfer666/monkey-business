import { test, assert, assertEq, run } from '../harness.uc';
import { initial, advance, sameContext, round, rebase, effective, fresh, aggregate } from '../../src/lib/health.uc';

function context(runtime) {
	return { boot: 'boot', outbound: 'outbound', runtime: runtime || 'runtime', method: 'method', network: 'network' };
}
const RULE = { id: 'rule', enabled: 1, requires_udp: 1 };

function policy(route, last) {
	return { id: 'rule', boot: 'boot', outbound: 'outbound', route: route, last_return: last };
}

function ready() {
	let c = context();
	let h = round(initial(c), c, 'success', 'success', 1);
	return round(h, c, 'success', 'success', 16);
}

test('HTTPS/UDP independent confirmation; unknown interrupts streak', function() {
	let h = ready(), c = context();
	h = round(h, c, 'success', 'failure', 31);
	assertEq(h.udp.state, 'up');
	h = round(h, c, 'success', 'unknown', 46);
	assertEq(h.udp.failures, 0);
	h = round(h, c, 'success', 'failure', 61);
	assertEq(h.udp.state, 'up');
	h = round(h, c, 'success', 'failure', 76);
	assertEq(h.udp.state, 'down');
	assertEq(h.https.state, 'up');
	assertEq(effective(RULE, null, h, true, 76).route, 'direct');
	assertEq(effective({ id: 'tcp', enabled: 1, requires_udp: 0 }, null, h, true, 76).route, 'proxy');
});

test('boot waits for two successes and first return has no artificial cooldown', function() {
	let c = context(), h = initial(c);
	assertEq(effective(RULE, null, h, true, 0).route, 'direct');
	h = round(h, c, 'success', 'success', 1);
	assertEq(effective(RULE, null, h, true, 1).route, 'direct');
	h = round(h, c, 'success', 'success', 16);
	let policy = effective(RULE, null, h, true, 16);
	assertEq(policy.route, 'proxy'); assert(policy.reset);
	assert(!effective(RULE, policy, h, true, 16).reset);
});

test('confirmed required down takes priority over helper unknown', function() {
	let h = ready(), c = context();
	h = round(h, c, 'failure', 'unknown', 31);
	h = round(h, c, 'failure', 'unknown', 46);
	let applied = effective(RULE, policy('proxy'), h, true, 46);
	assertEq(applied.route, 'direct'); assertEq(applied.reason, 'https_down'); assert(!applied.reset);
	h = round(h, c, 'unknown', 'success', 61);
	assertEq(effective(RULE, applied, h, true, 61).route, 'direct');
});

test('error preserves route, stale health is not new evidence', function() {
	let h = round(ready(), context(), 'unknown', 'unknown', 31);
	assertEq(effective(RULE, policy('proxy'), h, true, 31).route, 'proxy');
	assertEq(effective(RULE, policy('direct'), h, true, 31).route, 'direct');
	assert(!fresh(h, 77)); assert(!fresh(h, 30));
	assertEq(effective(RULE, policy('proxy'), h, true, 77).reason, 'stale_monitor');
});

test('cooldown readiness loss cancels pending return; exactly 60 seconds permits return', function() {
	let h = ready(), previous = policy('direct', 10);
	assertEq(effective(RULE, previous, h, true, 69).reason, 'stale_monitor');
	h = round(h, context(), 'success', 'success', 69);
	assertEq(effective(RULE, previous, h, true, 69).reason, 'return_cooldown');
	h = round(h, context(), 'unknown', 'success', 70);
	assertEq(effective(RULE, previous, h, true, 70).route, 'direct');
	h = round(h, context(), 'success', 'success', 85);
	assertEq(effective(RULE, previous, h, true, 85).route, 'direct');
	h = round(h, context(), 'success', 'success', 100);
	assert(effective(RULE, previous, h, true, 100).reset);
	assertEq(effective(RULE, previous, ready(), false, 16).reason, 'vpn_off');
});

test('generation fencing and reload retain policy, not the old diagnosis', function() {
	let h = ready(), next = context('runtime2');
	assertEq(round(h, next, 'success', 'success', 31).error, 'obsolete_round');
	let rebased = rebase(h, next);
	assertEq(rebased.https.state, 'unknown'); assertEq(rebased.https.successes, 0);
	assertEq(effective(RULE, policy('proxy'), rebased, true, 31).route, 'proxy');
	next.outbound = 'new';
	assertEq(rebase(h, next).https.state, 'unknown');
	assertEq(effective(RULE, policy('proxy'), rebase(h, next), true, 31).route, 'direct');
	assert(!sameContext({}, {}));
});

test('old down does not become fresh after unknown in a new method/network/runtime', function() {
	let h = ready();
	h = round(h, context(), 'failure', 'failure', 31);
	h = round(h, context(), 'failure', 'failure', 46);
	let c = context(); c.method = 'new';
	h = round(rebase(h, c), c, 'unknown', 'unknown', 61);
	assertEq(h.https.state, 'unknown');
	assertEq(effective(RULE, policy('direct'), h, true, 61).reason, 'awaiting_health');
});

test('invalid snapshot cannot publish a new policy even with ready signals', function() {
	let h = ready(); h.context = {};
	assert(!fresh(h, 16));
	assertEq(effective(RULE, policy('proxy'), h, true, 16), { error: 'invalid_context' });
	assertEq(effective(RULE, policy('direct'), h, true, 16), { error: 'invalid_context' });
});

test('two network failures versus internal errors and partial success', function() {
	assertEq(aggregate([{ state: 'failure' }, { state: 'failure' }]), 'failure');
	assertEq(aggregate([{ state: 'failure' }, { state: 'engine_error' }]), 'unknown');
	assertEq(aggregate([{ state: 'success' }, { state: 'engine_error' }]), 'success');
	assertEq(aggregate([{ state: 'failure' }]), 'unknown');
});

exit(run());
