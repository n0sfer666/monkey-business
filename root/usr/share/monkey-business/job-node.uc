import { readfile, popen, unlink } from 'fs';
import * as socket from 'socket';
import { privateJson, atomicPrivate } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/private-store.uc';
import { joinGroup } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/engine-group.uc';
import { spawnOwned, finished, collect, stopOwned } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/owned-process.uc';
import { ownsListener, processIdentity } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/listener.uc';
import { probeUdp } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/udp-probe.uc';
import { summarize } from '/usr/share/rpcd/ucode/lib/monkey-business/lib/availability.uc';
import { monotonic } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/routing-v2.uc';
import { shq } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/shell.uc';
let id = ARGV[0], index_ = ARGV[1], purpose = ARGV[2] || 'base';
if (type(id) != 'string' || match(id, /^[a-f0-9]{32}$/) == null ||
	match(index_ || '', /^[0-9]{1,3}$/) == null || int(index_) >= 200 || index(['base', 'extra'], purpose) < 0) exit(1);
let directory = '/tmp/mb-runtime/jobs/' + id;
let request = privateJson(directory + '/node-' + index_ + '.json', 32768);
if (request == null || !joinGroup(id, int(index_))) exit(1);
let diagnostics = request.diagnostic, bridge = null, bridgePid = null, bridgeIdentity = null;
let result;
try {
	if (request.hysteria) {
		let pidfile = directory + '/hy-' + index_ + '.pid';
		bridge = popen('umask 077; printf "%s\\n" "$$" > ' + shq(pidfile) +
			' || exit 1; exec /usr/share/monkey-business/job-engine.sh ' + id + ' hysteria ' + int(index_) + ' 2>/dev/null');
		let end = monotonic() + 2;
		while (monotonic() < end) {
			let pid = readfile(pidfile);
			if (pid != null && match(pid, /^[0-9]+\n$/) != null) {
				bridgePid = int(pid); bridgeIdentity = processIdentity(bridgePid);
				if (ownsListener(bridgePid, processIdentity(bridgePid), request.bridge_port)) break;
			}
			socket.poll(10);
		}
		if (bridgePid == null || !ownsListener(bridgePid, processIdentity(bridgePid), request.bridge_port))
			die('bridge_start_failed');
	}
	let pending = [], base = [], targets = request.targets;
	if (purpose == 'extra') targets = [request.extra_target];
	for (let i = 0; i < length(targets); i++) {
		let path = directory + '/https-' + index_ + '-' + i + '.json';
		if (!atomicPrivate(path, sprintf('%J', { diagnostic: diagnostics, target: targets[i], directory: directory }))) die('probe_request_write_failed');
		let child = spawnOwned(['ucode', '/usr/share/monkey-business/https-one.uc', path], directory, 8);
		if (child.error != null) die('probe_spawn_failed');
		push(pending, { path: path, child: child, index: i }); push(base, null);
	}
	let early = false;
	while (length(pending)) {
		let waiting = [];
		for (let task in pending) {
			if (!finished(task.child)) { push(waiting, task); continue; }
			let outcome = null, output = collect(task.child);
			try { outcome = output.error == null && output.code == 0 ? json(output.output) : null; } catch (e) {}
			base[task.index] = outcome || { state: 'engine_error', reason: 'https_method_failed' };
			if (request.early_stop && base[task.index].state == 'success') early = true;
			unlink(task.path);
		}
		pending = waiting;
		if (early) {
			for (let task in pending) {
				stopOwned(task.child); unlink(task.path); base[task.index] = { state: 'not_checked' };
			}
			pending = [];
		} else if (length(pending)) socket.poll(10);
	}
	if (purpose == 'extra') result = { extra: base[0] };
	else {
		result = summarize(base, null); result.base = base; result.base_finished = monotonic();
		result.udp = request.early_stop ? { state: 'not_checked' } : result.successes ? probeUdp(diagnostics) : { state: 'not_checked', reason: 'no_https_success' };
	}
} catch (e) { result = { state: 'engine_error', reason: 'node_method_failed', udp: { state: 'unknown' } }; }
// Finish the temporary bridge before publishing this node as terminal.
if (bridge != null && bridgePid != null) {
	let identity = bridgeIdentity;
	if (identity != null) system('kill -TERM ' + bridgePid + ' 2>/dev/null');
	let end = monotonic() + 1;
	while (identity != null && !finished({ pid: bridgePid, identity: identity }) && monotonic() < end) socket.poll(10);
	if (identity != null && !finished({ pid: bridgePid, identity: identity })) system('kill -KILL ' + bridgePid + ' 2>/dev/null');
	bridge.close();
}
print(sprintf('%J', result));
