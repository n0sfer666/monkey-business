'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { load } = require('./luci');

const msg = load('view.monkey-business.model.rulemsg');
const geo = load('view.monkey-business.model.geo');

test('every backend code has its own message', () => {
  const codes = {
    space: '',
    scheme: 'x.com',
    geo_empty: 'geoip',
    geo_name: 'geosite',
    slashes: '',
    ip4: '',
    ip6: '',
    mapped: '::ffff:1.2.3.4',
    port: 'x.com',
    matcher_empty: 'full',
    prefix: '32',
    path: 'x.com',
    wildcard: '',
    incomplete: '',
    not_full: 'corp',
    chars: '',
    tld: '',
  };

  for (const [code, arg] of Object.entries(codes))
    assert.notStrictEqual(msg.text({ code, arg }), 'Invalid entry', code);
  assert.strictEqual(msg.text({ code: 'prefix', arg: '128' }), 'Prefix must be 0–128');
  assert.strictEqual(msg.text({ code: 'not_full', arg: 'corp' }), 'Not a full domain, e.g. corp.com');
  assert.strictEqual(msg.text({ code: 'nope' }), 'Invalid entry');
});

test('mobile footer counts the other tab', () => {
  assert.strictEqual(msg.mobileFoot(3, 1), '3 lines need fixing · 1 on the other tab — fix to save');
  assert.strictEqual(msg.mobileFoot(1, 0), '1 line needs fixing — fix to save');
  assert.match(msg.mobileFoot(0, 0), /^One per line/);
});

test('geo summary shows sizes and the update date', () => {
  assert.strictEqual(
    geo.summary({ geoip: 16583067, geosite: 11147460, updated: 1791740441 }),
    'geoip 15.8 MB · geosite 10.6 MB · 2026-10-11',
  );
  assert.strictEqual(geo.summary({ geoip: 0, geosite: 5, updated: 0 }), 'geoip missing · geosite 0.0 MB');
  assert.strictEqual(geo.summary({}), '');
});
