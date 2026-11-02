'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { load } = require('./luci');

const schema = load('view.monkey-business.model.settings');
const datatype = load('view.monkey-business.model.datatype');
const rows = schema.sections.flatMap((s) => s.rows.map((r) => ({ sid: s.sid, ...r })));

test('sections match the UCI sections in order', () => {
  assert.deepStrictEqual(
    schema.sections.map((s) => s.sid),
    ['global', 'dns', 'anti_dpi'],
  );
});

test('options are unique within a section', () => {
  const keys = rows.map((r) => `${r.sid}.${r.opt}`);

  assert.strictEqual(new Set(keys).size, keys.length);
});

test('flags default to explicit 0 or 1', () => {
  for (const r of rows.filter((r) => r.kind === 'flag')) assert.ok(['0', '1'].includes(r.def), r.opt);
});

test('safety flags default to on', () => {
  const def = (opt) => rows.find((r) => r.opt === opt).def;

  assert.strictEqual(def('kill_switch'), '1');
  assert.strictEqual(def('ipv6_block'), '1');
});

test('select defaults are among the options', () => {
  for (const r of rows.filter((r) => r.kind === 'select'))
    assert.ok(
      r.options.some((o) => o.value === r.def),
      r.opt,
    );
});

test('checks exist and accept the default', () => {
  for (const r of rows.filter((r) => r.check)) {
    assert.strictEqual(typeof datatype[r.check], 'function', r.check);
    assert.strictEqual(datatype[r.check](r.def), null, r.opt);
  }
});

test('every row has a known kind and a label', () => {
  for (const r of rows) {
    assert.ok(['flag', 'select', 'text'].includes(r.kind), r.opt);
    assert.ok(r.label, r.opt);
  }
});
