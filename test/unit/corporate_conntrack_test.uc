import { test, assert, assertEq, run } from '../harness.uc';
import { originalTuple, returnedMatch, resetReturnedFlows } from '../../src/runtime/corporate-conntrack.uc';
import { shq } from '../../src/runtime/shell.uc';
const RULES = [{ id: 'exact', address: '8.8.8.8', port: '443' }, { id: 'wild', address: '8.8.8.8', port: '' }];
const POLICIES = { exact: { reset: false }, wild: { reset: true } };
test('extended family prefix and TCP state cannot hide the original tuple', function() {
	for (let prefix in ['tcp 6 120 ESTABLISHED', 'ipv4 2 tcp 6 120 ESTABLISHED']) {
		assertEq(originalTuple(prefix + ' src=10.0.0.2 dst=8.8.8.8 sport=1234 dport=443 src=8.8.8.8 dst=10.0.0.2 sport=443 dport=1234'),
			{ protocol: 'tcp', source: '10.0.0.2', destination: '8.8.8.8', sport: 1234, dport: 443 });
	}
	assertEq(originalTuple('udp 17 30 src=10.0.0.2 dst=8.8.8.8 sport=1234 dport=1194').dport, 1194);
});
test('exact-port exception and non-LAN source survive a wildcard return', function() {
	assert(!returnedMatch(RULES, POLICIES, '8.8.8.8', 443));
	let commands = [], lines = [];
	for (let source in ['10.0.0.2', '1.1.1.2'])
		for (let port in [443, 1194]) push(lines, 'ipv4 2 udp 17 30 src=' + source + ' dst=8.8.8.8 sport=1234 dport=' + port);
	let sh = { shq: shq, runCapture: function(cmd) {
		push(commands, cmd);
		if (index(cmd, 'conntrack -L') >= 0) return { ok: true, out: join('\n', lines) };
		if (index(cmd, 'ip -4 route get') >= 0) return { ok: true, out: index(cmd, '10.0.0.2') >= 0 ? '10.0.0.2 dev br-lan src 10.0.0.1' : '1.1.1.2 via 1.1.1.1 dev wan' };
		return { ok: true, out: '' };
	} };
	assertEq(resetReturnedFlows(sh, RULES, POLICIES, 'br-lan').deleted, 1);
	let deletes = filter(commands, function(cmd) { return index(cmd, 'conntrack -D') >= 0; });
	assertEq(length(deletes), 1); assert(index(deletes[0], '--dport 1194') > 0);
	assert(index(deletes[0], "--orig-src '10.0.0.2'") > 0);
});
test('route lookup failure is not a successful empty precise reset', function() {
 let sh = { shq: shq, runCapture: function(cmd) {
  return index(cmd, 'conntrack -L') >= 0 ? { ok: true, out: 'udp 17 30 src=10.0.0.2 dst=8.8.8.8 sport=1234 dport=1194' } : { ok: false };
 } };
 assertEq(resetReturnedFlows(sh, RULES, POLICIES, 'br-lan'), { state: 'failed', reason: 'route_lookup_failed', deleted: 0 });
});
exit(run());
