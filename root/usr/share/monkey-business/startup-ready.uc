// External init holds the shared mutation/procd locks throughout this hook.
import { readfile, unlink } from 'fs';
import * as socket from 'socket';
import * as sh from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/shell.uc';
import { privateJson, atomicPrivate } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/private-store.uc';
import { listenerOwner, acceptedOwner } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/engine-listener.uc';
import { endTransition } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/corporate-transition.uc';
import { directBypass } from '/usr/share/rpcd/ucode/lib/monkey-business/lib/bypass.uc';
let path = '/tmp/mb-runtime/startup.json', pending = privateJson(path, 4194304);
if (pending == null) exit(1);
let group = '/sys/fs/cgroup/monkey-business-engines/live', error = null;
if (ARGV[0] == 'abort-before-submit') {
	let restored = true;
	for (let file in pending.before) {
		if (pending.before[file] == null) unlink(file); else if (!atomicPrivate(file, pending.before[file])) restored = false;
	}
	let g = pending.old_config.global;
	let kernel = pending.old_kernel ?
		'MB_LAN_IFACE=' + sh.shq(g.lan_iface || 'br-lan') + ' MB_TPROXY_PORT=' + int(g.tproxy_port || 12345) +
		' MB_KILL_SWITCH=' + (g.kill_switch == '0' ? '0' : '1') + ' MB_DIRECT_BYPASS=' + (directBypass(g) ? '1' : '0') +
		' MB_FORCE_PROXY=' + sh.shq(g.custom_proxy || '') + ' timeout 5 sh /usr/share/monkey-business/firewall/apply.sh' :
		'timeout 5 sh /usr/share/monkey-business/firewall/flush.sh';
	if (!sh.runCapture(kernel + ' >/dev/null 2>&1').ok) restored = false;
	let owner = listenerOwner(group, 11800);
	if (pending.old_owner != null && sprintf('%J', owner) != sprintf('%J', pending.old_owner)) restored = false;
	if (!restored) error = 'rollback_failed';
} else {
	let until = +split(readfile('/proc/uptime'), ' ')[0] + 7, ready = false;
	while (+split(readfile('/proc/uptime'), ' ')[0] < until) {
		let x = listenerOwner(group, 11800), h = listenerOwner(group, 10810);
		if (x != null && (!pending.changed_xray || acceptedOwner(x, pending.blocked, null)) &&
			(pending.wants_bridge ? h != null && (!pending.changed_bridge || acceptedOwner(h, pending.blocked, null)) : h == null)) { ready = true; break; }
		socket.poll(20);
	}
	if (!ready) error = 'startup_not_ready';
}
if (error == null) error = endTransition(sh);
if (error != null) { atomicPrivate('/tmp/mb-runtime/routing-error.json', sprintf('%J', { error: error })); warn(error + '\n'); exit(1); }
unlink(path); unlink('/tmp/mb-runtime/routing-error.json');
