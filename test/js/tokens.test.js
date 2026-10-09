'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { load } = require('./luci');

const tokens = load('view.monkey-business.kit.tokens');

test('dark and light palettes define the same tokens', () => {
	assert.deepStrictEqual(Object.keys(tokens.light).sort(), Object.keys(tokens.dark).sort());
});

test('every token has a value', () => {
	for (const theme of [tokens.dark, tokens.light])
		for (const [key, value] of Object.entries(theme))
			assert.ok(/^(#[0-9a-f]{6}|rgba\([\d.,]+\))$/.test(value), `${key}: ${value}`);
});
