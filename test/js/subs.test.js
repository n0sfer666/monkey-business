'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { load } = require('./luci');

const subs = load('view.monkey-business.model.subs');
const confirm = load('view.monkey-business.model.confirmtext');
const GB = 1073741824;
const sec = (name, extra) => Object.assign({ '.name': name }, extra);

test('active is the wanted subscription, else the first one', () => {
	const list = [sec('a'), sec('b')];
	assert.strictEqual(subs.activeId(list, 'b'), 'b');
	assert.strictEqual(subs.activeId(list, 'gone'), 'a');
	assert.strictEqual(subs.activeId(list, ''), 'a');
	assert.strictEqual(subs.activeId([], 'a'), null);
});

test('masked url keeps only the scheme', () => {
	const masked = subs.maskUrl('https://panel.example/sub/secret-token');
	assert.strictEqual(masked, 'https://••••••/••••••');
	assert.ok(!masked.includes('secret') && !masked.includes('panel'));
	assert.strictEqual(subs.maskUrl('weird'), '••••••/••••••');
});

test('url errors match the add sheet hints', () => {
	assert.strictEqual(subs.urlError(''), 'URL is required');
	assert.strictEqual(subs.urlError('   '), 'URL is required');
	assert.strictEqual(subs.urlError('ftp://x/y'), 'Must start with http:// or https://');
	assert.strictEqual(subs.urlError('https://'), 'Must start with http:// or https://');
	assert.strictEqual(subs.urlError('https://a b'), 'Must start with http:// or https://');
	assert.strictEqual(subs.urlError(' https://panel/sub '), null);
	assert.strictEqual(subs.urlError('HTTP://panel/sub'), null);
});

test('traffic is shown only when the panel sent a limit', () => {
	assert.strictEqual(subs.traffic(sec('a', { total: '' })), null);
	assert.strictEqual(subs.traffic(sec('a', { total: '0' })), null);
	assert.deepStrictEqual(subs.traffic(sec('a', {
		total: String(100 * GB), used_upload: String(8 * GB), used_download: String(30 * GB), expire: '1800000000'
	})), { used: '38.0', total: '100.0', pct: 38, expire: '2027-01-15' });
	assert.strictEqual(subs.traffic(sec('a', { total: String(GB), used_download: String(3 * GB) })).pct, 100);
	assert.strictEqual(subs.traffic(sec('a', { total: String(GB) })).expire, null);
});

test('servers of a subscription include legacy ones without sub and skip manual', () => {
	const servers = [
		{ tag: 'a1', source: 'subscription', sub: 'a' },
		{ tag: 'm1', source: 'manual' },
		{ tag: 'l1', source: 'subscription' },
		{ tag: 'b1', source: 'subscription', sub: 'b' }
	];
	assert.deepStrictEqual(subs.serversOf(servers, 'a').map((s) => s.tag), ['a1']);
	assert.deepStrictEqual(subs.serversOf(servers, 'subscription').map((s) => s.tag), ['l1']);
});

test('a subscription is vacant without url and servers', () => {
	const servers = [{ tag: 'm1', source: 'manual' }, { tag: 'a1', source: 'subscription', sub: 'a' }];
	assert.strictEqual(subs.vacant(sec('subscription', { url: '' }), servers), true);
	assert.strictEqual(subs.vacant(sec('x', {}), servers), true);
	assert.strictEqual(subs.vacant(sec('a', { url: '' }), servers), false);
	assert.strictEqual(subs.vacant(sec('b', { url: 'https://b' }), servers), false);
	assert.strictEqual(subs.vacant(null, servers), false);
});

test('refetch lists subscriptions whose url is staged, once each', () => {
	const changes = [
		['set', 'a', 'url', 'https://x'], ['set', 'a', 'name', 'A'], ['set', 'a', 'url', 'https://y'],
		['set', 'cfg01', 'url', 'z'], ['remove', 'b'], ['set', 'b', 'url', 'https://b']
	];
	assert.deepStrictEqual(subs.refetch(changes, ['a', 'c']), ['a']);
	assert.deepStrictEqual(subs.refetch(undefined, ['a']), []);
});

test('default name counts from the existing subscriptions', () => {
	assert.strictEqual(subs.defaultName(1), 'Subscription 2');
	assert.strictEqual(subs.title(sec('sub_1', { name: '' })), 'sub_1');
	assert.strictEqual(subs.title(sec('sub_1', { name: 'Main' })), 'Main');
});

test('delete confirmation names the servers and the next active one', () => {
	assert.deepStrictEqual(confirm.deleteSub({ name: 'VPNON 2', count: 7 }), {
		title: 'Delete “VPNON 2”?', body: 'Its 7 servers are removed with it. Manual servers stay.'
	});
	assert.strictEqual(confirm.deleteSub({ name: 'A', count: 1, next: 'B' }).body,
		'Its 1 server is removed with it. Manual servers stay. It is the active subscription — “B” becomes active.');
	assert.strictEqual(confirm.deleteSub({ name: 'A', count: 0 }).body, 'It has no servers. Manual servers stay.');
});
