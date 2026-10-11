'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { load } = require('./luci');

const model = load('view.monkey-business.model.routing');

test('gfwlist chip matches the generator: gfw list for cn, only Via VPN elsewhere', () => {
	assert.ok(model.chips('gfwlist', 'cn').includes('geosite:gfw via VPN'));
	for (const region of ['ru', 'ir', 'other']) {
		const chips = model.chips('gfwlist', region);
		assert.ok(chips.includes('only your Via VPN list'), region);
		assert.ok(!chips.some(c => /geolocation|geosite/.test(c)), region);
	}
});

test('region chips follow the mode', () => {
	assert.deepStrictEqual(model.chips('bypass-local', 'ru'), ['geoip:ru direct', 'kernel bypass', 'DNS ru direct, rest DoH']);
	assert.deepStrictEqual(model.chips('global', 'other'), ['everything via VPN']);
	assert.ok(!model.chips('global', 'ru').includes('geoip:ru direct'));
});
