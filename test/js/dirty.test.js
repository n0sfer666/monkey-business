'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { load } = require('./luci');

const dirty = load('view.monkey-business.model.dirty');
const CONF = 'monkey-business';

function state(extra) {
  return Object.assign(
    {
      values: { [CONF]: { global: { kill_switch: '1', tproxy_port: '12345' } } },
      creates: {},
      changes: {},
      deletes: {},
      reorder: {},
    },
    extra,
  );
}

test('clean state is not pending', () => {
  assert.strictEqual(dirty.pending(state(), CONF), false);
});

test('changed option is pending', () => {
  const s = state({ changes: { [CONF]: { global: { tproxy_port: '1080' } } } });

  assert.strictEqual(dirty.pending(s, CONF), true);
});

test('option set back to its stored value is not pending', () => {
  const s = state({ changes: { [CONF]: { global: { kill_switch: '1' } } } });

  assert.strictEqual(dirty.pending(s, CONF), false);
});

test('new option on an existing section is pending', () => {
  const s = state({ changes: { [CONF]: { global: { log_level: 'debug' } } } });

  assert.strictEqual(dirty.pending(s, CONF), true);
});

test('created, deleted and reordered sections are pending', () => {
  assert.strictEqual(dirty.pending(state({ creates: { [CONF]: { cfg01: {} } } }), CONF), true);
  assert.strictEqual(dirty.pending(state({ deletes: { [CONF]: { global: { kill_switch: true } } } }), CONF), true);
  assert.strictEqual(dirty.pending(state({ reorder: { [CONF]: true } }), CONF), true);
});

test('changes of another config are ignored', () => {
  const s = state({ changes: { network: { lan: { proto: 'dhcp' } } }, creates: { network: { x: {} } } });

  assert.strictEqual(dirty.pending(s, CONF), false);
});

function typed(extra) {
  return state(
    Object.assign(
      {
        values: {
          [CONF]: {
            global: { '.type': 'global', active_sub: 'sub_a' },
            sub_a: { '.type': 'subscription', name: 'A' },
            cfg01: { '.type': 'server', name: 'S' },
          },
        },
      },
      extra,
    ),
  );
}

test('touched is false when only other section types changed', () => {
  const s = typed({
    changes: { [CONF]: { cfg01: { name: 'T' }, global: { active_sub: 'sub_b' } } },
    reorder: { [CONF]: true },
  });

  assert.strictEqual(dirty.touched(s, CONF, 'subscription'), false);
});

test('touched sees edits, creates and deletes of the type', () => {
  assert.strictEqual(
    dirty.touched(typed({ changes: { [CONF]: { sub_a: { name: 'B' } } } }), CONF, 'subscription'),
    true,
  );
  assert.strictEqual(
    dirty.touched(typed({ changes: { [CONF]: { sub_a: { name: 'A' } } } }), CONF, 'subscription'),
    false,
  );
  assert.strictEqual(
    dirty.touched(typed({ creates: { [CONF]: { sub_b: { '.type': 'subscription' } } } }), CONF, 'subscription'),
    true,
  );
  assert.strictEqual(dirty.touched(typed({ deletes: { [CONF]: { sub_a: true } } }), CONF, 'subscription'), true);
});
