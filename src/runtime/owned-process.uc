// All child argv values are internal paths/ports. Secrets stay in private configs.
import { popen, readfile, unlink, lsdir } from 'fs';
import * as socket from 'socket';
import { processIdentity } from './listener.uc';
import { shq } from './shell.uc';
import { nonce, privateDirectory, atomicPrivate, privateJson } from './private-store.uc';

function monotonic() { return +split(readfile('/proc/uptime'), ' ')[0]; }
function processState(pid) {
	let raw = readfile('/proc/' + pid + '/stat');
	if (raw == null) return null;
	return split(substr(raw, rindex(raw, ') ') + 2), ' ');
}
function spawnOwned(argv, directory, budget) {
	if (!privateDirectory(directory) || type(argv) != 'array' || !length(argv) ||
		type(budget) != 'int' || budget < 1 || budget > 240) return { error: 'invalid_process' };
	let pidfile = directory + '/pid-' + nonce();
	let command = 'umask 077; printf "%s\\n" "$$" > ' + shq(pidfile) +
		' || exit 1; i=0; while [ ! -f ' + shq(pidfile + '.ack') + ' ]; do ' +
		'i=$((i+1)); [ "$i" -lt 100 ] || exit 1; ucode -e ' +
		shq('import * as socket from "socket"; socket.poll(10);') + '; done; ' +
		'exec setsid timeout -k 2 ' + budget + ' ' + join(' ', map(argv, shq));
	let handle = popen(command);
	if (handle == null) return { error: 'spawn_failed' };
	let end = monotonic() + 1, pid = null;
	while (monotonic() < end) {
		let raw = readfile(pidfile);
		if (raw != null && match(raw, /^[0-9]+\n$/) != null) { pid = int(raw); break; }
		socket.poll(5);
	}
let anchored = pid != null ? processIdentity(pid) : null;
	let record = anchored != null ? directory + '/.owned-' + pid + '-' + anchored : null;
	if (pid != null && record != null && atomicPrivate(record, sprintf('%J', { pid: pid, identity: anchored })))
		atomicPrivate(pidfile + '.ack', 'ready');
	let readyEnd = monotonic() + 1;
	while (pid != null && monotonic() < readyEnd) {
		let state = processState(pid);
		if (state == null || state[0] == 'Z' || (int(state[2]) == pid && int(state[3]) == pid)) break;
		socket.poll(5);
	}
	unlink(pidfile); unlink(pidfile + '.ack');
	if (pid == null) { handle.close(); return { error: 'process_identity_missing' }; }
	let identity = processIdentity(pid);
	if (identity == null) {
		let output = handle.read('all'), code = handle.close();
		if (record != null) unlink(record);
		return { finished: true, output: output, code: code };
	}
	return { pid: pid, identity: identity, handle: handle, directory: directory, record: record };
}
function finished(child) {
	if (child.finished) return true;
	let state = processState(child.pid);
	return state == null || state[0] == 'Z' || processIdentity(child.pid) != child.identity;
}
function groupMembers(child) {
	let members = [];
	for (let name in (lsdir('/proc') || [])) {
		if (match(name, /^[0-9]+$/) == null) continue;
		let state = processState(int(name));
		if (state != null && state[0] != 'Z' && int(state[2]) == child.pid && int(state[3]) == child.pid)
			push(members, int(name));
	}
	return members;
}
function cleanGroup(child) {
	// Keep the unreaped leader as an identity anchor while terminating descendants,
	// including after a helper crash. Never signal a reused foreign PID/group.
	let state = processState(child.pid);
	if (state == null || processIdentity(child.pid) != child.identity) return false;
	if (int(state[2]) != child.pid || int(state[3]) != child.pid) return state[0] == 'Z';
	system('kill -TERM -- -' + child.pid + ' 2>/dev/null');
	let end = monotonic() + 2;
	while (length(groupMembers(child)) && monotonic() < end) socket.poll(10);
	if (length(groupMembers(child))) system('kill -KILL -- -' + child.pid + ' 2>/dev/null');
	end = monotonic() + 1;
	while (length(groupMembers(child)) && monotonic() < end) socket.poll(10);
	return !length(groupMembers(child));
}
function collect(child) {
	if (child.finished) return { output: child.output, code: child.code };
	if (!finished(child)) return { error: 'still_running' };
	if (!cleanGroup(child)) return { error: 'cleanup_failed' };
	let output = child.handle.read('all');
	let code = child.handle.close();
	child.finished = true; child.output = output; child.code = code;
	if (child.record != null) unlink(child.record);
	return { output: output, code: code };
}
function stopOwned(child) {
	if (child.finished) return true;
	if (!cleanGroup(child)) return false;
	let end = monotonic() + 1;
	while (!finished(child) && monotonic() < end) socket.poll(10);
	if (!finished(child)) return false;
	return collect(child).error == null;
}

function cleanOwnedDirectory(directory) {
	if (!privateDirectory(directory)) return false;
	let cleaned = true;
	for (let name in (lsdir(directory) || [])) {
		if (match(name, /^\.owned-[0-9]+-[0-9]+$/) == null) continue;
		let path = directory + '/' + name, child = privateJson(path, 4096);
		if (child == null || type(child.pid) != 'int' || type(child.identity) != 'string') { cleaned = false; continue; }
		if (processIdentity(child.pid) == child.identity && !cleanGroup(child)) { cleaned = false; continue; }
		unlink(path);
	}
	return cleaned;
}

export { spawnOwned, finished, collect, stopOwned, cleanOwnedDirectory };
