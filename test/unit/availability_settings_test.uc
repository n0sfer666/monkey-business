import { test, assert, assertEq, run } from '../harness.uc';
import { DEFAULT_TARGETS, normalizeTargets, normalizeTarget, curlConfig } from '../../src/lib/availability-settings.uc';
test('HTTPS targets normalize host, default port and path; require distinct hosts', function() {
	assertEq(normalizeTargets(DEFAULT_TARGETS).errors, []);
	assertEq(normalizeTarget({ url: 'HTTPS://Example.COM.:443', expected_status: 200 }).target.url, 'https://example.com/');
	assertEq(normalizeTargets([{ url: 'https://example.com/a', expected_status: 204 },
		{ url: 'https://EXAMPLE.COM.:0443/b', expected_status: 200 }]).errors[0].code, 'distinct_hosts_required');
});
test('URLs reject shell/config delimiters, userinfo, fragments and local literals', function() {
	for (let url in ['http://example.com/', 'https://user:pass@example.com/', 'https://example.com/#x',
		'https://127.0.0.1/', 'https://2130706433/', 'https://example.com/\nurl=x',
		'https://example.com\\@evil.com/', 'https://localhost/', 'https://8.8.8.8:0/'])
		assert(normalizeTarget({ url: url, expected_status: 204 }).error != null, url);
});
test('curl uses protected config instead of argv, no redirect or TLS bypass', function() {
	let cfg = curlConfig(DEFAULT_TARGETS[0], { port: 11800, credentials: { user: 'synthetic', pass: 'synthetic' } }, '/tmp/internal');
	assert(index(cfg, 'max-filesize = 4096') >= 0);
	assert(index(cfg, 'noproxy = ""') >= 0);
	assert(index(cfg, 'location') < 0); assert(index(cfg, 'insecure') < 0);
});
exit(run());
