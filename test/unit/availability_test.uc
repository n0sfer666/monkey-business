import { test, assert, assertEq, run } from '../harness.uc';
import { serverRef, refKey, resolveRef, summarize, fresh, compare, reorder } from '../../src/lib/availability.uc';

test('typed identity cannot collide across manual/subscription slash IDs', function() {
	let manual = { tag: 'sub/node' }, sub = { source: 'subscription', sub: 'sub', tag: 'node' };
	assert(refKey(serverRef(manual)) != refKey(serverRef(sub)));
	assertEq(resolveRef([manual, sub], serverRef(manual)).server, manual);
	assertEq(resolveRef([sub, sub], serverRef(sub)).error, 'identity_conflict');
	assertEq(resolveRef([sub], serverRef(manual)).error, 'unknown_server');
	let tag = '';
	for (let i = 0; i < 257; i++) tag += 'a';
	assertEq(refKey({ source: 'manual', tag: tag }), null);
});

test('base median and denominator never include extra; network versus method error', function() {
	let base = [{ state: 'success', latency_ms: 1200 }, { state: 'success', latency_ms: 1400 }];
	let result = summarize(base, { state: 'failure' });
	assertEq(result.state, 'degraded'); assertEq(result.latency_ms, 1300.0);
	assertEq(result.attempts, 2); assertEq(result.successes, 2);
	assertEq(summarize([{ state: 'success', latency_ms: 1200 },
		{ state: 'success', latency_ms: 1201 }]).latency_ms, 1200.5);
	assertEq(summarize(base, { state: 'engine_error' }).state, 'engine_error');
	assertEq(summarize([base[0], { state: 'failure' }]).state, 'degraded');
	assertEq(summarize([base[0], { state: 'engine_error' }]).state, 'engine_error');
	assertEq(summarize([{ state: 'failure' }, { state: 'failure' }]).latency_ms, null);
	assertEq(summarize([base[0]]).state, 'incomplete');
});

test('monotonic TTL belongs to base, not extra/publication/wall clock', function() {
	let record = { purpose: 'manual', base_finished: 10, extra_finished: 300, published: 309,
		fingerprint: 'fp', boot: 'boot', method: 'method', network: 'net' };
	let c = { fingerprint: 'fp', boot: 'boot', method: 'method', network: 'net' };
	assert(fresh(record, c, 309)); assert(!fresh(record, c, 310)); assert(!fresh(record, c, 9));
	c.fingerprint = 'new'; assert(!fresh(record, c, 20));
	c.fingerprint = 'fp'; c.boot = 'new'; assert(!fresh(record, c, 20));
	c.boot = 'boot'; record.purpose = 'active'; assert(!fresh(record, c, 20));
	assert(!fresh({ purpose: 'manual', base_finished: 1 }, {}, 2));
});

test('ranking classes, base successes, latency and stable nonrankable order', function() {
	let rows = [
		{ state: 'engine_error', order: 0, fresh: true },
		{ state: 'degraded', order: 1, fresh: true, successes: 1, latency_ms: 1 },
		{ state: 'available', order: 2, fresh: true, successes: 2, latency_ms: 1500 },
		{ state: 'available', order: 3, fresh: false, successes: 2, latency_ms: 1 },
		{ state: 'degraded', order: 4, fresh: true, successes: 2, latency_ms: 2000 },
		{ state: 'probe_failed', order: 5, fresh: true, successes: 0, latency_ms: null },
	];
	sort(rows, compare);
	assertEq(map(rows, function(r) { return r.order; }), [2, 4, 1, 5, 0, 3]);
});

test('order changes within group slots; wrong membership and incomplete lists rejected', function() {
	let a = { tag: 'a', disabled: '1' }, b = { tag: 'b' },
		x = { source: 'subscription', sub: 'sub', tag: 'x' },
		y = { source: 'subscription', sub: 'sub', tag: 'y' };
	let input = [a, x, b, y];
	let groups = [[serverRef(b), serverRef(a)], [serverRef(y), serverRef(x)]];
	assertEq(reorder(input, groups).servers, [b, y, a, x]);
	assertEq(reorder(input, [[serverRef(a), serverRef(x)]]).error, 'mixed_group');
	assertEq(reorder(input, [[serverRef(a), serverRef(b)]]).error, 'incomplete_permutation');
	assertEq(reorder(input, [[serverRef(a), serverRef(a)]]).error, 'invalid_permutation');
});

exit(run());
