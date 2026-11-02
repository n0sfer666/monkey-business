'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { load } = require('./luci');

const servers = load('view.monkey-business.model.servers');
const order = load('view.monkey-business.model.order');
const write = load('view.monkey-business.model.serverwrite');
const link = load('view.monkey-business.model.linktext');
const confirm = load('view.monkey-business.model.confirmtext');
const sidmap = load('view.monkey-business.model.sidmap');

const sub = (name, tag) => ({ '.name': name, tag, source: 'subscription', sub: 'sub_a' });
const man = (name, tag) => ({ '.name': name, tag, source: 'manual' });

test('title falls back to the endpoint when the tag is missing', () => {
  assert.strictEqual(servers.title({ tag: 'RU' }), 'RU');
  assert.strictEqual(servers.title({ address: '192.0.2.10', port: '443' }), '192.0.2.10:443');
  assert.strictEqual(servers.title({ address: '2001:db8::1', port: 443 }), '[2001:db8::1]:443');
});

test('protocol label never shows a bare none', () => {
  assert.strictEqual(servers.protocol({ protocol: 'vless', security: 'reality' }), 'vless / reality');
  assert.strictEqual(servers.protocol({ protocol: 'vless', security: 'none' }), 'vless / no TLS');
  assert.strictEqual(servers.protocol({ protocol: 'vless' }), 'vless');
  assert.strictEqual(servers.protocol({ protocol: 'hysteria2', security: 'tls' }), 'hysteria2');
});

test('filters list subscriptions with servers and manual only when present', () => {
  const list = [sub('s1', 'a'), man('m1', 'b')];
  const subs = [
    { id: 'sub_a', name: 'VPNON' },
    { id: 'sub_b', name: 'Empty' },
  ];

  assert.deepStrictEqual(
    servers.filters(list, subs).map((f) => f.value),
    ['all', 'sub_a', 'manual'],
  );
  assert.deepStrictEqual(
    servers.filtered(list, 'manual').map((s) => s['.name']),
    ['m1'],
  );
  assert.deepStrictEqual(
    servers.filtered(list, 'sub_a').map((s) => s['.name']),
    ['s1'],
  );
  assert.strictEqual(servers.filtered(list, 'all').length, 2);
});

test('orphans of a removed subscription are hidden, manual servers stay', () => {
  const list = [sub('s1', 'a'), { '.name': 's2', source: 'subscription', sub: 'gone' }, man('m1', 'b')];

  assert.deepStrictEqual(
    servers.visible(list, ['sub_a']).map((s) => s['.name']),
    ['s1', 'm1'],
  );
  assert.strictEqual(servers.visible(list, []).length, 3);
});

test('availability is semantic, fresh and independent of latency cutoffs', () => {
  assert.strictEqual(servers.ping(null).kind, 'unknown');
  assert.strictEqual(servers.ping({ state: 'available', fresh: true, ms: 1500 }).kind, 'available');
  assert.strictEqual(servers.ping({ state: 'available', fresh: false }).kind, 'unknown');
  assert.strictEqual(servers.pingOf({ latency_ms: 40, auto_disabled: true }).state, 'unknown');
});

test('off accepts every uci truthy spelling', () => {
  for (const v of ['1', 'true', 'yes', 'on']) assert.ok(servers.isOff({ disabled: v }));
  assert.ok(!servers.isOff({ disabled: '0' }));
  assert.ok(!servers.isOff({}));
});

test('sort by ping is stable and puts unmeasured last', () => {
  const ranks = { a: Infinity, b: 80, c: 40, d: Infinity, e: 80 };

  assert.deepStrictEqual(
    order.sorted(['a', 'b', 'c', 'd', 'e'], (id) => ranks[id]),
    ['c', 'b', 'e', 'a', 'd'],
  );
  assert.strictEqual(servers.rank({ na: true, ms: null }), Infinity);
  assert.strictEqual(servers.rank({ ms: 1500, state: 'available', successes: 2, fresh: true }), 1500);
});

test('chain of moves reproduces the wanted order', () => {
  let list = ['a', 'b', 'c', 'd'];
  const move = (sid, prev, after) => {
    list = list.filter((x) => x !== sid);
    list.splice(list.indexOf(prev) + (after ? 1 : 0), 0, sid);
  };

  order.chain(['d', 'a', 'c', 'b'], move);
  assert.deepStrictEqual(list, ['d', 'a', 'c', 'b']);
});

test('placing a tile takes the target place from either side', () => {
  assert.deepStrictEqual(order.place(['a', 'b', 'c', 'd'], 'a', 'c'), { ids: ['b', 'c', 'a', 'd'], after: true });
  assert.deepStrictEqual(order.place(['a', 'b', 'c', 'd'], 'd', 'b'), { ids: ['a', 'd', 'b', 'c'], after: false });
  assert.strictEqual(order.place(['a', 'b'], 'a', 'a'), null);
  assert.strictEqual(order.place(['a', 'b'], 'x', 'a'), null);
  assert.strictEqual(order.neighbour(['a', 'b'], 'a', -1), null);
  assert.strictEqual(order.neighbour(['a', 'b'], 'a', 1), 'b');
});

test('writing a link replaces the server and drops stale and legacy options', () => {
  const current = {
    '.name': 'cfg1',
    '.type': 'server',
    tag: 'old',
    name: 'Manual 1',
    disabled: '1',
    transport: '{"type":"ws"}',
    reality: '{"publicKey":"x"}',
    obfs: 'null',
    pbk: 'OLD',
    tr_path: '/old',
  };
  const flat = {
    tag: 'new',
    protocol: 'vless',
    port: 443,
    pbk: '',
    tr_type: 'tcp',
    tr_path: '',
    alpn: '',
    source: 'manual',
  };
  const ops = Object.fromEntries(write.ops(current, flat, ''));

  assert.deepStrictEqual(ops, {
    tag: 'new',
    protocol: 'vless',
    port: '443',
    pbk: null,
    tr_type: 'tcp',
    tr_path: null,
    alpn: null,
    source: 'manual',
    name: null,
    transport: null,
    reality: null,
    obfs: null,
  });
  assert.ok(!('disabled' in ops));
  assert.strictEqual(Object.fromEntries(write.ops(null, flat, 'Mine')).tag, 'Mine');
});

test('relink puts the current name into the link fragment', () => {
  assert.strictEqual(
    write.relink('vless://u@h:443?type=tcp#old', 'Мой 🚀'),
    'vless://u@h:443?type=tcp#' + encodeURIComponent('Мой 🚀'),
  );
  assert.strictEqual(write.relink('hy2://p@h:443/', 'a#b'), 'hy2://p@h:443/#a%23b');
});

test('link verdict levels', () => {
  assert.strictEqual(link.verdict(null).level, 'idle');
  assert.strictEqual(link.verdict({ error: 'empty' }).level, 'idle');
  assert.deepStrictEqual(link.verdict({ error: 'unsupported_scheme', detail: 'vmess' }), {
    level: 'error',
    text: 'Protocol vmess is not supported',
  });
  assert.strictEqual(link.verdict({ error: 'whatever' }).text, 'This link cannot be used');
  assert.deepStrictEqual(link.verdict({ ok: true, warnings: ['duplicate'], duplicate: 'RU' }), {
    level: 'warn',
    text: 'Valid, but this server is already in the list as “RU”',
  });
  assert.deepStrictEqual(link.verdict({ ok: true, warnings: [] }), { level: 'ok', text: 'Valid link' });
});

test('link chips summarise what was recognised', () => {
  assert.deepStrictEqual(
    link.chips({ protocol: 'vless', address: 'h', port: 443, security: 'reality', tr_type: 'xhttp', flow: '' }),
    ['VLESS', 'h:443', 'Reality', 'XHTTP'],
  );
  assert.deepStrictEqual(
    link.chips({
      protocol: 'vless',
      address: 'h',
      port: 443,
      security: 'tls',
      tr_type: 'tcp',
      flow: 'xtls-rprx-vision',
    }),
    ['VLESS', 'h:443', 'TLS', 'TCP', '+xtls-rprx-vision'],
  );
  assert.deepStrictEqual(
    link.chips({ protocol: 'hysteria2', address: 'h', port: 443, obfs_type: 'salamander', mport: '20000-30000' }),
    ['Hysteria2', 'h:443', 'salamander', 'ports 20000-30000'],
  );
  assert.deepStrictEqual(link.chips({ protocol: 'hysteria2', address: 'h', port: 443 }), [
    'Hysteria2',
    'h:443',
    'no obfs',
  ]);
});

test('delete texts differ for manual and subscription servers', () => {
  assert.deepStrictEqual(confirm.deleteServer({ name: 'X' }), {
    title: 'Delete “X”?',
    body: 'It is a manual server, so it is removed for good. To bring it back, add its link again.',
  });
  assert.match(confirm.deleteServer({ name: 'X', sub: 'VPNON' }).body, /next update of “VPNON”/);
});

test('saved sections are matched to their temporary names by content, not by position', () => {
  const made = {
    new01: { '.name': '0', '.type': 'server', tag: 'A', port: '443', alpn: ['h2'] },
    new02: { '.name': 'cfg0c', '.type': 'server', tag: 'B', port: '443' },
    new03: { '.name': 'cfg0d', '.type': 'server', tag: 'B', port: '443' },
  };
  const fresh = [
    { '.name': 'cfg0c', '.type': 'server', tag: 'A', port: '443', alpn: ['h2'] },
    { '.name': 'cfg0d', '.type': 'server', tag: 'B', port: '443' },
    { '.name': 'cfg0e', '.type': 'server', tag: 'B', port: '443' },
  ];

  assert.deepStrictEqual(sidmap.match(made, fresh), { new01: 'cfg0c', new02: 'cfg0d', new03: 'cfg0e' });
  assert.deepStrictEqual(
    sidmap.match({ new01: { tag: 'A', port: 443 } }, [{ '.name': 'cfg0c', tag: 'A', port: '443' }]),
    {},
  );
  assert.deepStrictEqual(sidmap.match({ new01: { tag: 'A' } }, [{ '.name': 'cfg0c', tag: 'A', port: '1' }]), {});
  assert.deepStrictEqual(
    sidmap.match({ new01: { '.type': 'server', tag: 'A' } }, [{ '.name': 'cfg0c', '.type': 'subscription', tag: 'A' }]),
    {},
  );
});

test('wanted order is rewritten to saved names and drops sections that are gone', () => {
  assert.deepStrictEqual(
    sidmap.order(['new01', 'cfg02', 'cfg01', 'new02'], { new01: 'cfg05' }, ['cfg01', 'cfg02', 'cfg05']),
    ['cfg05', 'cfg02', 'cfg01'],
  );
});
