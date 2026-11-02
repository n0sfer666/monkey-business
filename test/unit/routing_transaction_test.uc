import { test, assertEq, run } from '../harness.uc';
import { applyRouting } from '../../src/lib/routing-transaction.uc';

const CANDIDATE = { mode: 'global', region: 'other', direct: '', proxy: '', corporate_rules: [] };
function fixture(fault) {
	let events = [], cache = {}, revision = 'r1', generation = 'g1', enabled = true, runtime = 'e1';
	let state = function() { return { revision: revision, generation: generation, runtime: runtime, enabled: enabled, outbound: {} }; };
	let ctx = {
		localAddresses: function() { return []; },
		requestResult: function(id) { return cache[id]; },
		routingSnapshot: state,
		prepareRouting: function() {
			push(events, 'prepare');
			if (fault == 'race') generation = 'g2';
			if (fault == 'runtime_race') runtime = 'e2';
			return fault == 'prepare' ? { error: 'invalid_xray' } : {};
		},
		lockMutation: function() { push(events, 'lock'); return fault != 'busy'; },
		unlockMutation: function() { push(events, 'unlock'); },
		discardRouting: function() { push(events, 'discard'); },
		installRouting: function() { push(events, 'install'); return fault == 'install' ? 'nft_failed' : null; },
		verifyRouting: function() { push(events, 'verify'); return fault == 'verify' ? 'runtime_failed' : null; },
		commitRouting: function() { push(events, 'commit'); return fault == 'commit' ? 'uci_failed' : null; },
		publishRouting: function() { push(events, 'publish'); revision = 'r2'; return fault == 'publish' || fault == 'rollback' ? 'snapshot_failed' : null; },
		restoreRouting: function() { push(events, 'restore'); revision = 'r1'; return fault == 'rollback' ? 'restore_failed' : null; },
		recordRequest: function(id, body, result) { cache[id] = { body: body, result: result }; },
	};
	return { ctx: ctx, events: events, args: { request_id: 'request_00000001', expected_revision: 'r1', candidate: CANDIDATE } };
}

test('routing transaction commits only after runtime verification', function() {
	let f = fixture();
	assertEq(applyRouting(f.ctx, f.args), { ok: true, status: 'applied', revision: 'r2' });
	assertEq(f.events, ['prepare', 'lock', 'install', 'verify', 'commit', 'publish', 'unlock', 'discard']);
	let count = length(f.events);
	assertEq(applyRouting(f.ctx, f.args).ok, true);
	assertEq(length(f.events), count);
	f.args.candidate = { ...CANDIDATE, region: 'ru' };
	assertEq(applyRouting(f.ctx, f.args).error, 'request_id_reused');
});

test('each failed install phase compensates and unlocks', function() {
	for (let phase in ['install', 'verify', 'commit', 'publish', 'rollback']) {
		let f = fixture(phase);
		assertEq(applyRouting(f.ctx, f.args).error, phase == 'rollback' ? 'rollback_failed' : 'apply_failed');
		assertEq(slice(f.events, -3), ['restore', 'unlock', 'discard']);
	}
});

test('generation race and busy lock do not install or overwrite newer runtime', function() {
	let f = fixture('race');
	assertEq(applyRouting(f.ctx, f.args).error, 'runtime_conflict');
	assertEq(f.events, ['prepare', 'lock', 'unlock', 'discard']);
	f = fixture('runtime_race');
	assertEq(applyRouting(f.ctx, f.args).error, 'runtime_conflict');
	assertEq(f.events, ['prepare', 'lock', 'unlock', 'discard']);
	f = fixture('busy');
	assertEq(applyRouting(f.ctx, f.args).error, 'busy');
	assertEq(f.events, ['prepare', 'lock', 'discard']);
});

test('validation and revision conflict cannot start runtime preparation', function() {
	let f = fixture();
	f.args.request_id = '../bad';
	assertEq(applyRouting(f.ctx, f.args).error, 'invalid_request');
	assertEq(f.events, []);
	f = fixture(); f.args.expected_revision = 'old';
	assertEq(applyRouting(f.ctx, f.args).error, 'revision_conflict');
	assertEq(f.events, []);
});

test('corporate transition guard is released only after durable request result', function() {
 let f = fixture(), record = f.ctx.recordRequest;
 f.ctx.recordRequest = function(id, body, result) { push(f.events, 'persist'); record(id, body, result); };
 f.ctx.finishRouting = function() { push(f.events, 'release'); return null; };
 assertEq(applyRouting(f.ctx, f.args).ok, true);
 assertEq(slice(f.events, -5), ['publish', 'persist', 'release', 'unlock', 'discard']);
});
test('cache failure restores under the guard; persistent failure keeps it closed', function() {
 for (let persistent in [false, true]) {
  let f = fixture(), record = f.ctx.recordRequest, calls = 0;
  f.ctx.recordRequest = function(id, body, result) { calls++; if (persistent || calls == 1) die('synthetic storage failure'); record(id, body, result); };
  f.ctx.finishRouting = function() { push(f.events, 'release'); return null; };
  assertEq(applyRouting(f.ctx, f.args).error, persistent ? 'rollback_failed' : 'apply_failed');
  assertEq(index(f.events, 'restore') >= 0, true);
  assertEq(index(f.events, 'release') >= 0, !persistent);
 }
});
exit(run());
