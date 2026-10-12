'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { load } = require('./luci');

const datatype = load('view.monkey-business.model.datatype');

test('port accepts 1..65535', () => {
  for (const v of ['1', '80', '12345', '65535']) assert.strictEqual(datatype.port(v), null, v);
});

test('port rejects out of range and non-numbers', () => {
  for (const v of ['', '0', '65536', '123456', 'abc', '12a', '-1', '1.5', ' 80'])
    assert.ok(datatype.port(v), JSON.stringify(v));
});
