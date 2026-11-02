// Runs in the disposable unit container, against synthetic files only.
import { test, assert, assertEq, run } from '../harness.uc';
import { mkdir, readfile, unlink } from 'fs';
import { applyRuntime } from '../../src/runtime/apply.uc';
import { atomicPrivate, privateDirectory } from '../../src/runtime/private-store.uc';
import { loadApplied } from '../../src/runtime/applied.uc';
import { shq } from '../../src/runtime/shell.uc';

const CONF = '/etc/monkey-business';
const DIR = '/tmp/mb-runtime';
const FILES = [CONF + '/xray.json', CONF + '/hysteria.json', CONF + '/applied.json',
	DIR + '/corporate-sets.nft', DIR + '/corporate.json', DIR + '/firewall-applied', '/usr/share/xray/geoip.dat', '/usr/share/xray/geosite.dat'];
mkdir(CONF, 0o700); mkdir('/usr/share/xray', 0o755); assert(privateDirectory(DIR));
let saved = {};
for (let file in FILES) saved[file] = readfile(file);
atomicPrivate('/usr/share/xray/geoip.dat', 'synthetic');
atomicPrivate('/usr/share/xray/geosite.dat', 'synthetic');
function fixture(fault) {
	atomicPrivate(CONF + '/xray.json', '{"old":true}');
	atomicPrivate(CONF + '/hysteria.json', '{"auth":"synthetic-old"}');
	let reloads = 0, firewalls = 0;
	let sh = { shq: shq, runCapture: function(cmd) {
		if (index(cmd, 'xray run -test') >= 0) return { ok: fault != 'validation', out: '' };
		if (index(cmd, '/etc/init.d/monkey-business reload') >= 0) {
			reloads++;
			if (fault == 'reload' && reloads == 1) return { ok: false, out: '' };

			let token = match(cmd, /MB_APPLY_TOKEN=([a-f0-9]{32})/);
			atomicPrivate(DIR + '/firewall-applied', token[1]);
			return { ok: true, out: '' };
		}
		if (index(cmd, 'firewall/apply.sh') >= 0) { firewalls++; return { ok: fault != 'firewall' || firewalls > 1, out: '' }; }
		return { ok: true, out: '' };
	} };
	return applyRuntime(sh);
}
const CONFIG = { global: { enabled: '1' }, server: { tag: 'synthetic' }, corporate_rules: [] };

test('failed validation cannot remove the working Hysteria bridge', function() {
	let app = fixture('validation');
	assertEq(app.applyConfig('{"new":true}', false, CONFIG, null, { json: null }), 'xray config validation failed');
	assertEq(readfile(CONF + '/hysteria.json'), '{"auth":"synthetic-old"}');
	assertEq(readfile(CONF + '/xray.json'), '{"old":true}');
});
test('reload and firewall failures restore predecessor files', function() {
	for (let phase in ['reload', 'firewall']) {
		let app = fixture(phase);
		assertEq(app.applyConfig('{"new":true}', false, CONFIG, null, { json: null }), phase == 'reload' ? 'runtime_reload_failed' : 'runtime_firewall_failed');
		assertEq(readfile(CONF + '/hysteria.json'), '{"auth":"synthetic-old"}');
		assertEq(readfile(CONF + '/xray.json'), '{"old":true}');
	}
});
test('successful apply records an independent private server snapshot', function() {
	let app = fixture();
	assertEq(app.applyConfig('{"new":true}', false, CONFIG, null, { json: null }), null);
	assertEq(loadApplied().config, CONFIG);
	assertEq(readfile(CONF + '/hysteria.json'), null);
	assertEq(readfile(CONF + '/xray.json'), '{"new":true}');
});
let rc = run();
for (let file in FILES) {
	if (saved[file] == null) unlink(file);
	else atomicPrivate(file, saved[file]);
}
exit(rc);
