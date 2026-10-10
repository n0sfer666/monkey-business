'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { load } = require('./luci');

const iv = load('view.monkey-business.model.interval');

test('clamp keeps 0 as off and pins the rest to 10..120', () => {
	assert.deepStrictEqual([0, 5, 10, 90, 120, 500].map(iv.clamp), [0, 10, 10, 90, 120, 120]);
	assert.deepStrictEqual(['', 'abc', '-5', '45'].map(iv.clamp), [0, 0, 0, 45]);
});

test('config seconds read as minutes, the old day shows as 120', () => {
	assert.strictEqual(iv.fromConfig('1', '3600'), 60);
	assert.strictEqual(iv.fromConfig('1', '86400'), 120);
	assert.strictEqual(iv.fromConfig('1', '300'), 10);
	assert.strictEqual(iv.fromConfig('1', ''), 60);
	assert.strictEqual(iv.fromConfig(undefined, '5400'), 0);
	assert.strictEqual(iv.fromConfig('', '5400'), 0);
	assert.strictEqual(iv.fromConfig('0', '5400'), 0);
});

test('minutes write back as seconds within 600..7200, 0 only turns auto-update off', () => {
	assert.deepStrictEqual(iv.toConfig(90), { auto_update: '1', update_interval: '5400' });
	assert.deepStrictEqual(iv.toConfig(3), { auto_update: '1', update_interval: '600' });
	assert.deepStrictEqual(iv.toConfig(999), { auto_update: '1', update_interval: '7200' });
	assert.deepStrictEqual(iv.toConfig(0), { auto_update: '0' });
});

test('text reads like the mockup', () => {
	assert.deepStrictEqual([0, 10, 60, 90, 120].map(iv.text),
		['off', 'every 10 min', 'every 1 h', 'every 1 h 30 min', 'every 2 h']);
});

test('note warns about clamping and explains 0', () => {
	assert.strictEqual(iv.note('0').warn, false);
	assert.match(iv.note('').text, /0 = off/);
	assert.deepStrictEqual(iv.note('5'), { text: 'Minimum is 10 min, will be saved as 10', warn: true });
	assert.deepStrictEqual(iv.note('300'), { text: 'Maximum is 120 min, will be saved as 120', warn: true });
	assert.strictEqual(iv.note('45').warn, false);
});

test('digits drops everything but three digits', () => {
	assert.strictEqual(iv.digits('1a2b3c4'), '123');
	assert.strictEqual(iv.digits(null), '');
});
