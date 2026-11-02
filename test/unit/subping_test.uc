import { test, assert, assertEq, run } from '../harness.uc';
import * as h from '../../src/rpcd/handlers.uc';
import { selectWorking, probeCost } from '../../src/rpcd/select.uc';
import * as ping from '../../src/rpcd/ping.uc';
import { serversList } from '../../src/rpcd/status.uc';
import { NOW, srv, manual, sub, mkState, mockCtx } from '../subfixtures.uc';
function state() { return mkState([srv('a', '1.0.0.1', 'sub'), srv('b', '1.0.0.2', 'sub')], [sub('sub')], 'sub'); }
test('TCP failure/latency cache never filters full VPN confirmations', function() {
	let s = state(); s.pingDown = { 'sub/a': true }; s.pingStore = { 'sub/a': { ms: null } };
	assertEq(selectWorking(mockCtx(s)).server.tag, 'a');
	assertEq(s.probed, ['a']); assertEq(s.pinged, []);
	let view = serversList(mockCtx(s)).servers[0];
	assertEq(view.auto_disabled, false); assertEq(view.latency_ms, null);
});
test('cap counts candidates, no unconfirmed fallback or provisional selection', function() {
	let s = state(); s.cap = 1; s.probeFail = { 'sub/a': true };
	assertEq(selectWorking(mockCtx(s)).error, 'no_working_server');
	assertEq(s.probed, ['a']); assertEq(s.selected, '');
	s = state(); s.probeFail = { 'sub/a': true, 'sub/b': true };
	assertEq(h.configApply(mockCtx(s)).error, 'no_working_server'); assertEq(s.applies, 0);
});
test('disabled nodes remain listed but are never selected; Hysteria uses full probes', function() {
	let s = state(); s.servers[0].disabled = '1'; s.servers[1].protocol = 'hysteria2';
	assertEq(selectWorking(mockCtx(s)).server.tag, 'b'); assertEq(s.probed, ['b']);
	assertEq(length(serversList(mockCtx(s)).servers), 2);
});
test('expired/short caller budgets cannot install unconfirmed candidates', function() {
	for (let budget in [0, 1, probeCost(state().servers[0]) - 1]) {
		let s = state(); let result = h.configApply(mockCtx(s), { deadline: NOW + budget });
		assert(result.error != null); assertEq(s.applies, 0); assertEq(s.probed, []);
	}
	let s = state(); s.probeFail = { 'sub/a': true };
	assertEq(selectWorking(mockCtx(s), NOW + probeCost(s.servers[0]) + 1).error, 'probe_deadline');
	assertEq(s.probed, ['a']);
});
test('all old ping RPC handlers are deprecated without invoking root network work', function() {
	let s = state(); let ctx = mockCtx(s);
	for (let result in [ping.serversPing(ctx), ping.subscriptionPing(ctx, { sub: 'sub' }), ping.serverPing(ctx, { id: 'sub/a' })])
		assertEq(result, { api_version: 2, error: 'deprecated', replacement: 'availability_start' });
	assertEq(s.pinged, []); assertEq(s.probed, []);
});
exit(run());
