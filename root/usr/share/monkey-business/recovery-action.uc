import * as uci from 'uci';
import { readfile } from 'fs';
import * as socket from 'socket';
import { acquireMutation } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/mutation.uc';
import { processIdentity } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/listener.uc';
import { loadApplied } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/applied.uc';
import { privateJson } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/private-store.uc';
import { monotonic } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/routing-v2.uc';
import * as sh from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/shell.uc';
let action = ARGV[0];
if (index(['0', '1', '2', '3', 'retry', 'stop'], action) < 0) exit(1);
function fence() {
	let c = uci.cursor(), applied = loadApplied();
	if (c.get('monkey-business', 'global', 'enabled') != '1' || applied == null) return null;
	return sprintf('%J', [applied.generation, applied.epoch, privateJson('/tmp/mb-runtime/intent.json', 4096)]);
}
let lock = acquireMutation();
if (lock == null) exit(1);
let expected = ARGV[1];
if (type(expected) != 'string' || fence() != expected) { lock.close(); exit(0); }
let processes = [];
if (action == '0' || action == '1') {
	for (let raw in split(trim(readfile('/sys/fs/cgroup/monkey-business-engines/live/cgroup.procs') || ''), '\n')) {
		let pid = int(raw), identity = processIdentity(pid), cmd = readfile('/proc/' + pid + '/cmdline') || '';
		if (identity != null && (index(cmd, '/etc/monkey-business/xray.json') >= 0 || index(cmd, '/etc/monkey-business/hysteria.json') >= 0)) {
			push(processes, { pid: pid, identity: identity }); system('kill -TERM ' + pid + ' 2>/dev/null');
		}
	}
}
lock.close();
if (action == '1') {
	let end = monotonic() + 8;
	while (monotonic() < end) {
		let alive = filter(processes, function(p) { return processIdentity(p.pid) == p.identity; });
		if (!length(alive)) break;
		socket.poll(50);
	}
}
if (action == '2' || action == '3' || action == 'retry') {
	// Candidate probes and all long network waits are outside the mutation lock.
	let result = sh.runCapture('timeout 90 ubus -t 88 call monkey-business config_apply \'{"deadline":' + (time() + 70) + '}\' 2>/dev/null');
	let application = null;
	try { application = result.ok ? json(result.out) : null; } catch (e) {}
	let accepted = application != null && application.ok === true && application.error == null && application.skipped == null;
	if (action == '2' || action == 'retry') exit(accepted ? 0 : 1);
	if (!accepted) exit(1);
	// A successful candidate installation changes the fence deliberately.
	if (type(application.runtime_fence) != 'string' || fence() != application.runtime_fence) exit(0);
	expected = application.runtime_fence;
}
lock = acquireMutation();
if (lock == null) exit(1);
if (fence() != expected || expected == null) { lock.close(); exit(0); }
if (action == '1')
	for (let p in processes) if (processIdentity(p.pid) == p.identity) system('kill -KILL ' + p.pid + ' 2>/dev/null');
let result = true;
if (action == 'stop' || action == '3') result = sh.runCapture('MB_APPLYING=1 timeout 20 /etc/init.d/monkey-business stop >/dev/null 2>&1').ok;
if (action == '1' || action == '3') result = sh.runCapture('MB_APPLYING=1 /etc/init.d/monkey-business start >/dev/null 2>&1').ok && result;
lock.close(); exit(result ? 0 : 1);
