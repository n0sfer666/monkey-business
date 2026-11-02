import { test, assertEq, assertThrows, run } from '../harness.uc';
import { generate, generateProbe } from '../../src/generator/xray.uc';

import { parse } from '../../src/parser/subscription.uc';
import { readfile } from 'fs';
const SERVER = parse(readfile('test/fixtures/sub_urilist.txt')).servers[0];
const WILD = { id: 'wild', name: 'wild', address: '8.8.8.8', enabled: 1, port: '' };
const EXACT = { id: 'exact', name: 'exact', address: '8.8.8.8', enabled: 0, port: '53' };

test('probe cannot escape via direct_dns destination exception', function() {
	let out = generateProbe({ server: SERVER, dns: { direct_dns: '8.8.8.8' } });
	assertEq(out.routing.rules[0].inboundTag, ['probe']);
	assertEq(out.routing.rules[0].outboundTag, 'proxy');
	assertEq(out.routing.rules[1].ip, ['8.8.8.8']);
});

test('corporate exact wins wildcard and custom rules in every mode', function() {
	for (let mode in ['global', 'bypass-local', 'gfwlist']) {
		let out = generate({ server: SERVER, corporate_rules: [WILD, EXACT],
			global: { routing_mode: mode, custom_direct: '8.8.8.8' },
			dns: { direct_dns: '8.8.8.8' } });
		assertEq(out.routing.rules[0], { type: 'field', inboundTag: ['tproxy-in'],
			ip: ['8.8.8.8/32'], network: 'tcp,udp', outboundTag: 'direct', port: '53' });
		assertEq(out.routing.rules[1].outboundTag, 'proxy');
		assertEq(out.routing.rules[1].port, null);
		assertEq(out.routing.rules[1].inboundTag, ['tproxy-in']);
	}
});

test('generator rejects invalid off rules and local interface addresses', function() {
	assertThrows(function() { generate({ server: SERVER,
		corporate_rules: [{ id: 'bad', name: 'bad', address: '127.0.0.1', enabled: 0 }] }); });
	assertThrows(function() { generate({ server: SERVER,
		corporate_rules: [WILD], local_addresses: ['8.8.8.8'] }); });
});

exit(run());
