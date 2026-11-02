import { test, assert, assertEq, run } from '../harness.uc';
import { routeIdentity } from '../../src/lib/network-epoch.uc';
function v4(use, gateway) { return 'Iface Destination Gateway Flags RefCnt Use Metric Mask MTU Window IRTT\neth0 00000000 ' + (gateway || '0102000A') + ' 0003 1 ' + use + ' 10 00000000 0 0 0\n'; }
function v6(ref, use) { return '00000000000000000000000000000000 00 00000000000000000000000000000000 00 fe800000000000000000000000000001 00000400 ' + ref + ' ' + use + ' 00000003 eth0\n'; }
test('traffic and reference counters cannot invalidate health or manual ranking', function() {
	assertEq(routeIdentity(v4('0'), v6('00000001', '00000000')), routeIdentity(v4('43'), v6('00000004', '00000032')));
});
test('WAN route/address/link change invalidates the epoch', function() {
	assert(sprintf('%J', routeIdentity(v4('0'), '', ['1.1.1.1'])) != sprintf('%J', routeIdentity(v4('0', '0202000A'), '', ['1.1.1.1'])));
	assert(sprintf('%J', routeIdentity(v4('0'), '', ['1.1.1.1'])) != sprintf('%J', routeIdentity(v4('0'), '', ['1.1.1.2'])));
});
exit(run());
