import * as uci from 'uci';
import * as socket from 'socket';
import { readfile, unlink } from 'fs';
import * as sh from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/shell.uc';
import { privateDirectory, atomicPrivate, privateJson, nonce } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/private-store.uc';
import { storeApplied, loadApplied } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/applied.uc';
import { spawnOwned, stopOwned } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/owned-process.uc';
import { listenerOwner } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/engine-listener.uc';
import { generateDiagnostics } from '/usr/share/rpcd/ucode/lib/monkey-business/generator/xray.uc';
import { declarations } from '/usr/share/rpcd/ucode/lib/monkey-business/generator/corporate-nft.uc';
import { observer } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/observer.uc';
let root = '/tmp/mb-runtime', configPath = root + '/live-test.json';
if (!privateDirectory('/etc/monkey-business') || !privateDirectory(root + '/uci')) die('directory failed');
let c = uci.cursor();
c.set('monkey-business', 'global', 'global'); c.set('monkey-business', 'global', 'enabled', '1');
c.set('monkey-business', 'availability', 'availability');
for (let i = 0; i < 2; i++) {
	c.set('monkey-business', 'availability', 'target' + (i + 1) + '_url', 'https://' + (i ? 'two' : 'one') + '.fixture.example:18443/ok');
	c.set('monkey-business', 'availability', 'target' + (i + 1) + '_status', '204');
}
if (!c.commit('monkey-business')) die('synthetic UCI failed');
let server = { tag: 'synthetic-live', protocol: 'vless', address: '10.0.2.2', port: 14080,
	uuid: '11111111-2222-3333-4444-555555555555', encryption: 'none', security: 'none', transport: { type: 'tcp' } };
let health = { port: 11800, credentials: { user: nonce(), pass: nonce() } };
let rules = [{ id: 'https_rule', name: 'HTTPS', address: '8.8.4.4', port: '443', enabled: true, requires_udp: false },
	{ id: 'udp_rule', name: 'UDP', address: '8.8.4.4', port: '', enabled: true, requires_udp: true }];
let config = { server: server, health: health, corporate_rules: rules, global: { lan_iface: 'br-lan' } };
if (!storeApplied(config)) die('applied snapshot failed');
let generated = generateDiagnostics({ candidates: [{ server: server, ...health }] });
atomicPrivate(root + '/observer-table.nft', 'table inet monkey_business { ' + declarations(rules, {}) + '\n}\n');
if (!sh.runCapture('nft -f ' + root + '/observer-table.nft').ok) die('nft setup failed');
let engine = null;
function startEngine(blockUdp) {
	if (engine != null && !stopOwned(engine)) die('live cleanup failed');
	let runtime = json(sprintf('%J', generated));
	if (blockUdp) {
		push(runtime.outbounds, { tag: 'udp-block', protocol: 'blackhole', settings: {} });
		unshift(runtime.routing.rules, { type: 'field', network: 'udp', outboundTag: 'udp-block' });
	}
	atomicPrivate(configPath, sprintf('%J', runtime));
	engine = spawnOwned(['/usr/share/monkey-business/engine-run.sh', '/usr/bin/xray', 'run', '-c', configPath], root, 100);
	if (engine.error != null) die('live start failed');
	for (let i = 0; i < 200 && listenerOwner('/sys/fs/cgroup/monkey-business-engines/live', 11800) == null; i++) socket.poll(10);
	if (listenerOwner('/sys/fs/cgroup/monkey-business-engines/live', 11800) == null) die('live listener failed');
}
atomicPrivate(root + '/corporate.json', sprintf('%J', { rules: rules, policies: {} }));
let monitor = observer(sh, function() { return uci.cursor('/etc/config', root + '/uci'); });
try {
	startEngine(false);
	monitor.tick(); monitor.tick();
	let before = privateJson(root + '/health.json', 65536);
	if (before == null || before.https.state != 'up') die('HTTPS observer failed: ' + sprintf('%J', before));
	let prior = privateJson(root + '/corporate.json', 65536);
	if (prior.policies.https_rule.route != 'proxy') die('healthy HTTPS did not return proxy');
	startEngine(true);
	monitor.tick();
	let first = privateJson(root + '/health.json', 65536);
	if (first.https.successes != 1 || first.udp.failures != 1) die('epoch did not reset independent streaks');
	let policy = privateJson(root + '/corporate.json', 65536);
	if (policy.policies.https_rule.route != 'proxy') die('reload lost applied route');
	monitor.tick();
	let next = privateJson(root + '/health.json', 65536);
	policy = privateJson(root + '/corporate.json', 65536);
	if (next.https.state != 'up' || next.udp.state != 'down' || policy.policies.https_rule.route != 'proxy' || policy.policies.udp_rule.route != 'direct')
		die('HTTPS/UDP independence failed: ' + sprintf('%J', next));
	print('PASS: real active observer, independent UDP fallback and epoch preservation\n');
} catch (e) {
	if (engine != null) stopOwned(engine);
	die(e);
}
if (engine != null && !stopOwned(engine)) die('live cleanup failed');
c.set('monkey-business', 'global', 'enabled', '0'); c.commit('monkey-business');
monitor.tick();
if (readfile(root + '/health.json') != null) die('Off still observed');
print('PASS: Off stops observation without activating VPN\n');
