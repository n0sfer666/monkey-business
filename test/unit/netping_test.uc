// Subscription transfer security replaces the removed TCP latency implementation.
import { test, assert, assertEq, run } from '../harness.uc';
import { readfile, lstat } from 'fs';
import { atomicPrivate } from '../../src/runtime/private-store.uc';
import { netRuntime } from '../../src/runtime/net.uc';
function fixture(ok) {
	let calls = [];
	let net = netRuntime({ runCapture: function(cmd) {
		push(calls, cmd);
		assert(index(cmd, 'synthetic-token') < 0, 'URL leaked into argv');
		let config = match(cmd, /--config ([^ ]+\/curl.conf)/)[1];
		assertEq(lstat(config).mode & 0o777, 0o600);
		let directory = replace(config, /\/curl.conf$/, '');
		assertEq(lstat(directory).mode & 0o777, 0o700);
		assert(index(readfile(config), 'synthetic-token') >= 0);
		atomicPrivate(directory + '/body', 'synthetic-prefix');
		atomicPrivate(directory + '/headers', 'Subscription-Userinfo: total=1234\n');
		return { ok: ok, code: ok ? 0 : 18, out: '' };
	} });
	return { net: net, calls: calls };
}
test('protected URL/config and successful HTTPS response with bounded metadata', function() {
	let f = fixture(true), result = f.net.fetchSubscription('https://endpoint.example/sub?token=synthetic-token');
	assertEq(result, { body: 'synthetic-prefix', userinfo: 'total=1234' }); assertEq(length(f.calls), 1);
});
test('truncated transfer is rejected despite a nonempty, parseable prefix', function() {
	assertEq(fixture(false).net.fetchSubscription('https://endpoint.example/sub?token=synthetic-token'), null);
});
test('HTTP/URL controls cannot start a transfer', function() {
	let f = fixture(true);
	assertEq(f.net.fetchSubscription('http://endpoint.example/sub'), null);
	assertEq(f.net.fetchSubscription('https://endpoint.example/\noutput=/tmp/unsafe'), null);
	assertEq(f.calls, []);
});
exit(run());
