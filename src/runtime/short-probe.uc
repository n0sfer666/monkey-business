// Candidate confirmation uses the same isolated engines/HTTPS helper as manual jobs.
import { open, unlink, lsdir, rmdir, readfile } from 'fs';
import * as socket from 'socket';
import { privateDirectory, atomicPrivate, privateJson, nonce } from './private-store.uc';
import { groupPath, prepareGroup, cleanGroup } from './engine-group.uc';
import { processIdentity } from './listener.uc';
import { listenerOwner } from './engine-listener.uc';
import { spawnOwned, finished, collect, stopOwned, cleanOwnedDirectory } from './owned-process.uc';
import { acquireSlots, releaseSlots } from './probe-slots.uc';
import { monotonic } from './routing-v2.uc';
import { generateDiagnostics } from '../generator/xray.uc';
import { isHysteria, hysteriaConfigJson } from '../generator/hysteria.uc';
function shortProbeResult(sh, dns, server, targets) {
	if (!privateDirectory('/tmp/mb-runtime') || !privateDirectory('/tmp/mb-runtime/jobs')) return { ok: false, reason: 'busy_or_dependency' };
	let lock = open('/tmp/mb-runtime/short-probe.lock', 'ae', 0o600);
	if (lock == null) return { ok: false, reason: 'busy_or_dependency' };
	if (!lock.lock('xn')) { lock.close(); return { ok: false, reason: 'busy_or_dependency' }; }
	let id = nonce(), directory = '/tmp/mb-runtime/jobs/' + id, engine = null, node = null, slots = null, success = false, stage = 'preparation';
	try {
		if (!privateDirectory(directory)) die('dependency_failed');
		let pid = int(split(readfile('/proc/self/stat'), ' ')[0]);
		if (!atomicPrivate(directory + '/owner.json', sprintf('%J', { pid: pid, identity: processIdentity(pid), active: true })) ||
			prepareGroup(id) == null) die('dependency_failed');
		let candidate = { server: server, port: 12261, bridge_port: 12262,
			credentials: { user: nonce(), pass: nonce() }, bridge_credentials: { user: nonce(), pass: nonce() } };
		if (!atomicPrivate(directory + '/xray.json', sprintf('%J', generateDiagnostics({ candidates: [candidate], dns: dns })))) die('write_failed');
		stage = 'offline_validation';
		if (!sh.runCapture('timeout 5 xray run -test -c ' + directory + '/xray.json >/dev/null 2>&1').ok) die('invalid_candidate');
		if (isHysteria(server) && !atomicPrivate(directory + '/hy-0.json', hysteriaConfigJson(server,
			{ socksPort: candidate.bridge_port, credentials: candidate.bridge_credentials }))) die('write_failed');
		stage = 'slots';
		let end = monotonic() + 3;
		while (slots == null && monotonic() < end) { slots = acquireSlots('manual', true); if (slots == null) socket.poll(20); }
		if (slots == null) die('slots_busy');
		stage = 'engine_start';
		engine = spawnOwned(['/usr/share/monkey-business/job-engine.sh', id, 'xray'], directory, 16);
		if (engine.error != null) die('engine_failed');
		end = monotonic() + 2;
		while (listenerOwner(groupPath(id), candidate.port) == null && monotonic() < end) socket.poll(10);
		stage = 'listener_ownership';
		let owner = listenerOwner(groupPath(id), candidate.port);
		if (owner == null) die('listener_missing');
		if (!atomicPrivate(directory + '/node-0.json', sprintf('%J', { diagnostic: { ...owner, port: candidate.port,
			credentials: candidate.credentials }, targets: targets, hysteria: isHysteria(server), bridge_port: candidate.bridge_port,
			early_stop: true }))) die('write_failed');
		stage = 'node_start';
		node = spawnOwned(['ucode', '/usr/share/monkey-business/job-node.uc', id, '0', 'base'], directory, 12);
		if (node.error != null) die('node_failed');
		end = monotonic() + 12;
		while (!finished(node) && monotonic() < end) socket.poll(20);
		if (!finished(node)) die('timeout');
		stage = 'node_result';
		let result = collect(node);
		let row = result.error == null && result.code == 0 ? json(result.output) : null;
		success = row != null && row.successes > 0;
		if (!success && row != null) stage = row.reason || row.state || 'confirmation_failed';
	} catch (e) { success = false; }
	if (!cleanGroup(id)) { success = false; stage = 'kernel_cleanup'; }
	if (node != null && node.handle != null && !stopOwned(node)) { success = false; stage = 'node_cleanup'; }
	if (engine != null && engine.handle != null && !stopOwned(engine)) { success = false; stage = 'engine_cleanup'; }
	if (slots != null) releaseSlots(slots);
	let cleaned = cleanGroup(id) && cleanOwnedDirectory(directory);
	atomicPrivate(directory + '/owner.json', '{"active":false}');
	if (cleaned) {
		for (let file in (lsdir(directory) || [])) unlink(directory + '/' + file);
		rmdir(directory);
	} else success = false;
	lock.close();
	return { ok: success, reason: success ? null : stage };
}
function shortProbe(sh, dns, server, targets) { return shortProbeResult(sh, dns, server, targets).ok; }
export { shortProbe, shortProbeResult };
