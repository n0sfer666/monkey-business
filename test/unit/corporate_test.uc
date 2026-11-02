import { test, assert, assertEq, run } from '../harness.uc';
import { publicIpv4, normalizeRules, normalizeRouting, orderedRules, matchRule } from '../../src/lib/corporate.uc';

function rule(id, port) {
	return { id: id, name: '  Туннель  ', address: '8.8.4.4', port: port, enabled: 1 };
}

function repeated(value, count) {
	let out = '';
	for (let i = 0; i < count; i++) out += value;
	return out;
}

test('public IPv4 strict syntax and special-purpose boundaries', function() {
	for (let address in ['0.1.2.3', '10.0.0.1', '127.0.0.1', '100.64.0.0', '100.127.255.255',
		'169.254.0.1', '172.16.0.0', '172.31.255.255', '192.168.0.1', '192.0.0.9',
		'192.0.2.1', '192.88.99.1', '198.18.0.1', '198.19.255.255', '198.51.100.10',
		'203.0.113.1', '224.0.0.0', '255.255.255.255', '8.08.4.4', '8.8.4.256',
		'8.8.4.4/32', '134743044', '0x08080404', ' 8.8.4.4', 'example.com', '::1'])
		assert(!publicIpv4(address), address);
	for (let address in ['8.8.4.4', '100.63.255.255', '100.128.0.0', '172.15.255.255',
		'172.32.0.0', '198.17.255.255', '198.20.0.0', '223.255.255.255'])
		assert(publicIpv4(address), address);
	assert(!publicIpv4('8.8.4.4', ['8.8.4.4']));
});

test('canonical port, trimmed Unicode name, safe defaults', function() {
	let result = normalizeRules([rule('r1', '00443')]);
	assertEq(result.errors, []);
	assertEq(result.rules[0], { id: 'r1', name: 'Туннель', address: '8.8.4.4',
		port: '443', enabled: 1, requires_udp: 1 });
	let raw = rule('r1', ''); delete raw.enabled;
	assertEq(normalizeRules([raw]).rules[0].enabled, 0);
	assertEq(normalizeRules([raw]).rules[0].port, '');
});

test('name limit is Unicode codepoints and controls are rejected', function() {
	let raw = rule('r1', '');
	raw.name = repeated('я', 64);
	assertEq(normalizeRules([raw]).errors, []);
	raw.name += 'я';
	assert(length(normalizeRules([raw]).errors) > 0);
	for (let name in ['', 'a\nb', 'a\tb', 'a\x7fb', 'a\xc2\x85b', '\xed\xa0\x80', '\xf4\x90\x80\x80']) {
		raw.name = name;
		assert(length(normalizeRules([raw]).errors) > 0);
	}
});

test('bad ports and invalid disabled rules cannot be saved', function() {
	for (let port in ['0', '65536', '-1', '+1', '1.5', '1-2', '1,2', ' 53', true, []])
		assert(length(normalizeRules([rule('r1', port)]).errors) > 0);
	let raw = rule('r1', '443'); raw.enabled = 0; raw.address = '10.0.0.1';
	assert(length(normalizeRules([raw]).errors) > 0);
});

test('canonical duplicate pair forbidden regardless of flags; IDs stable and unique', function() {
	let a = rule('a', '00443'), b = rule('b', '443'); b.enabled = 0;
	assertEq(normalizeRules([a, b]).errors[0].code, 'duplicate_pair');
	b.port = ''; b.id = 'a';
	assertEq(normalizeRules([a, b]).errors[0].code, 'duplicate_id');
	let many = [];
	for (let i = 0; i < 33; i++) push(many, rule('r' + i, '' + (i + 1)));
	assertEq(normalizeRules(many).errors[0].code, 'invalid_count');
});

test('exact rule is terminal before wildcard for both TCP and UDP', function() {
	let wild = rule('wild', ''), exact = rule('exact', '53'); exact.enabled = 0;
	for (let rules in [[wild, exact], [exact, wild]]) {
		assertEq(orderedRules(rules)[0].id, 'exact');
		for (let protocol in ['tcp', 'udp']) {
			assertEq(matchRule(rules, '8.8.4.4', 53, protocol).id, 'exact');
			assertEq(matchRule(rules, '8.8.4.4', 443, protocol).id, 'wild');
		}
		assertEq(matchRule(rules, '8.8.4.4', 53, 'icmp'), null);
		assertEq(matchRule(rules, '8.8.4.5', 53, 'tcp'), null);
	}
});

test('routing candidate rejects foreign fields, types and size', function() {
	let c = { mode: 'global', region: 'ru', direct: '', proxy: '', corporate_rules: [] };
	assertEq(normalizeRouting(c).errors, []);
	c.servers = [];
	assertEq(normalizeRouting(c).errors[0].code, 'unexpected_field');
	delete c.servers; c.direct = repeated('a', 65537);
	assertEq(normalizeRouting(c).errors[0].code, 'invalid_list');
	c.direct = 1;
	assertEq(normalizeRouting(c).errors[0].code, 'invalid_list');
});

test('invalid IDs are never echoed or amplified in validation errors', function() {
	let raw = rule(repeated('a', 120000), ''); raw.name = ''; raw.address = '';
	let result = normalizeRules([raw]);
	assert(length(sprintf('%J', result)) < 1024);
	for (let error in result.errors) { assertEq(error.id, null); assertEq(error.index, 0); }
});

exit(run());
