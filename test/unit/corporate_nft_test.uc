import { test, assert, assertEq, run } from '../harness.uc';
import { declarations, update, elements } from '../../src/generator/corporate-nft.uc';
import { planPolicy } from '../../src/runtime/corporate.uc';
import { initial } from '../../src/lib/health.uc';
const RULES = [
	{ id: 'wild', name: 'x', address: '8.8.8.8', enabled: 1, port: '' },
	{ id: 'exact', name: 'x', address: '8.8.8.8', enabled: 0, port: '53' }
];
test('nft sets preserve exact ownership and reject stale proxy for off', function() {
	let sets = elements(RULES, { wild: { route: 'proxy' }, exact: { route: 'proxy' } });
	assertEq(sets.corp_exact_direct, ['8.8.8.8 . 53']);
	assertEq(sets.corp_exact_proxy, []);
	assertEq(sets.corp_wild_proxy, ['8.8.8.8']);
	assert(index(declarations(RULES, {}), 'corp_wild_direct') >= 0);
	let script = update(RULES, {});
	assertEq(length(split(script, 'flush set')) - 1, 4);
	assert(index(script, 'delete table') < 0);
});
test('boot seeds direct for all enabled corporate rules', function() {
	let health = initial({ boot: 'b', outbound: 'g', runtime: 'r', method: 'm', network: 'n' });
	let result = planPolicy(RULES, {}, health, true, 0, false);
	assertEq(result.policies.wild.route, 'direct');
	assertEq(result.policies.exact.route, 'direct');
});
exit(run());
