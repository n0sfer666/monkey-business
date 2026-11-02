import { rememberRecord } from './availability-records.uc';
import { readfile, unlink, lsdir } from 'fs';
import * as socket from 'socket';
import { privateJson, atomicPrivate, nonce } from './private-store.uc';
import { jobPath, readJob, writeJob, finishJob } from './jobs.uc';
import { prepareGroup, cleanGroup, groupPath, cleanNode } from './engine-group.uc';
import { spawnOwned, finished, collect, stopOwned } from './owned-process.uc';
import { ownsListener, processIdentity } from './listener.uc';
import { acquireSlots, releaseSlots } from './probe-slots.uc';
import { monotonic } from './routing-v2.uc';
import { fingerprint } from './fingerprint.uc';
import { outboundPayload } from '../lib/outbound.uc';
import { generateDiagnostics } from '../generator/xray.uc';
import { isHysteria, hysteriaConfigJson } from '../generator/hysteria.uc';
import { summarize, compare, serverRef } from '../lib/availability.uc';
import { PROBE_BASE, BRIDGE_BASE } from '../lib/diagnostic.uc';

function listenerOwner(id, port) {
	for (let raw in split(trim(readfile(groupPath(id) + '/cgroup.procs') || ''), '\n')) {
		let pid = int(raw), identity = processIdentity(pid);
		if (ownsListener(pid, identity, port)) return { pid: pid, identity: identity };
	}
	return null;
}
const PROGRAM = '/usr/share/monkey-business/';
function runJob(sh, job, enabled, context) {
	let directory = jobPath(job.job_id), definition = privateJson(directory + '/definition.json', 4194304);
	if (definition == null || prepareGroup(job.job_id) == null) {
		finishJob(job, 'failed', 'job_dependency_failed'); return;
	}
	job.state = 'running'; job.worker = context; job.base_completed = 0;
	writeJob(job);
 function stamp(row, index_) {
  return { ...row, base_finished: row.base_finished != null ? row.base_finished : monotonic(),
   purpose: 'manual', fingerprint: fingerprint(outboundPayload(definition.servers[index_])),
   method: definition.method.revision, network: definition.network, boot: definition.boot };
 }
	let engine = null, active = [], queue = [], candidates = [], terminal = 'completed', reason = null;
	try {
		for (let i = 0; i < length(definition.servers); i++) {
			if (readfile(directory + '/cancel') != null) die('cancelled');
			if (monotonic() >= job.deadline - 10) die('deadline');
			let server = definition.servers[i];
			if (isHysteria(server) && !sh.runCapture('test -x /usr/bin/hysteria').ok) {
				job.rows[i] = stamp({ ...job.rows[i], state: 'unsupported', reason: 'hysteria_missing' }, i);
				if (!rememberRecord(job.rows[i])) die('result_cache_failed'); job.completed++; job.base_completed++;
				continue;
			}
			let candidate = { server: server, port: PROBE_BASE + i, bridge_port: BRIDGE_BASE + i,
				credentials: { user: nonce(), pass: nonce() }, bridge_credentials: { user: nonce(), pass: nonce() } };
			let config;
			try { config = generateDiagnostics({ candidates: [candidate], dns: definition.method.dns }); }
			catch (e) { config = null; }
			let validation = directory + '/validate-' + i + '.json';
			if (config == null || !atomicPrivate(validation, sprintf('%J', config)) ||
				!sh.runCapture('timeout 5 xray run -test -c ' + validation + ' >/dev/null 2>&1').ok) {
				job.rows[i] = stamp({ ...job.rows[i], state: 'config_error', reason: 'candidate_validation_failed' }, i);
				if (!rememberRecord(job.rows[i])) die('result_cache_failed'); job.completed++; job.base_completed++;
				unlink(validation); continue;
			}
			unlink(validation);
			if (isHysteria(server) && !atomicPrivate(directory + '/hy-' + i + '.json',
				hysteriaConfigJson(server, { socksPort: candidate.bridge_port, credentials: candidate.bridge_credentials })))
				die('job_write_failed');
			candidate.index = i; push(candidates, candidate); push(queue, i);
		}
		writeJob(job);
		if (length(candidates)) {
			if (!atomicPrivate(directory + '/xray.json', sprintf('%J', generateDiagnostics({ candidates: candidates, dns: definition.method.dns }))))
				die('job_write_failed');
			engine = spawnOwned([PROGRAM + 'job-engine.sh', job.job_id, 'xray'], directory,
				max(1, int(job.deadline - monotonic())));
			if (engine.error != null || engine.pid == null) die('engine_start_failed');
			let end = min(job.deadline - 10, monotonic() + 3);
			for (let candidate in candidates) {
				while (monotonic() < end && listenerOwner(job.job_id, candidate.port) == null) socket.poll(10);
				let owner = listenerOwner(job.job_id, candidate.port);
				if (owner == null) die('engine_listener_failed');
				if (!atomicPrivate(directory + '/node-' + candidate.index + '.json', sprintf('%J', {
					diagnostic: { pid: owner.pid, identity: owner.identity, port: candidate.port, credentials: candidate.credentials },
					targets: definition.method.targets, hysteria: isHysteria(candidate.server), bridge_port: candidate.bridge_port })))
					die('job_write_failed');
			}
		}
		let extra = false;
		while (length(queue) || length(active) || !extra) {
			if (readfile(directory + '/cancel') != null) { terminal = 'cancelled'; reason = 'user_cancelled'; break; }
			if (monotonic() >= job.deadline - 10) { terminal = 'incomplete'; reason = reason == 'recovery_preemption' ? reason : 'deadline'; break; }
			let recovering = privateJson('/tmp/mb-runtime/recovery.json', 4096);
			while (length(queue) && (recovering == null || !recovering.active)) {
				let slots = acquireSlots('manual', enabled());
				if (slots == null) break;
				let index_ = shift(queue);
				let child = spawnOwned(['ucode', PROGRAM + 'job-node.uc', job.job_id, '' + index_, extra ? 'extra' : 'base'],
					directory, min(14, max(1, int(job.deadline - monotonic() - 10))));
				if (child.error != null) { releaseSlots(slots); die('node_spawn_failed'); }
				push(active, { child: child, index: index_, slots: slots });
				if (!extra) job.rows[index_].state = 'checking';
			}
			let pending = [];
			for (let task in active) {
				if (!finished(task.child)) { push(pending, task); continue; }
				if (!cleanNode(job.job_id, task.index)) die('node_cleanup_failed');
				let collected = collect(task.child), result;
				releaseSlots(task.slots);
				if (collected.error != null) die('node_cleanup_failed');
				try { result = collected.code == 0 ? json(collected.output) : null; } catch (e) { result = null; }
				if (result == null) result = { state: 'engine_error', reason: 'node_failed', udp: { state: 'unknown' } };
				let row = job.rows[task.index];
				if (extra) {
					let summary = summarize(row.base, result.extra || { state: 'engine_error' });
					row = { ...row, ...summary, extra: result.extra, phase: null }; job.completed++;
				} else {
					row = stamp({ ...row, ...result, order: task.index, fresh: true }, task.index);
					job.base_completed++;
					if (row.successes > 0) row.phase = 'awaiting_extra';
					else job.completed++;
				}
				if (!rememberRecord(row)) die('result_cache_failed');
				job.rows[task.index] = row;
			}
			active = pending;
			if (!length(queue) && !length(active) && !extra) {
				extra = true;
				let ranked = sort(filter(job.rows, function(row) { return row.successes > 0; }), compare);
				for (let row in slice(ranked, 0, 5)) {
					let request = privateJson(directory + '/node-' + row.order + '.json', 32768);
					request.extra_target = definition.method.targets[row.base[0].state == 'success' ? 0 : 1];
					if (!atomicPrivate(directory + '/node-' + row.order + '.json', sprintf('%J', request))) die('job_write_failed');
					row.phase = 'extra';
					push(queue, row.order);
				}
				for (let row in job.rows) if (row.phase == 'awaiting_extra') { row.phase = null; if (!rememberRecord(row)) die('result_cache_failed'); job.completed++; }
			}
			writeJob(job);
			if (recovering != null && recovering.active) reason = 'recovery_preemption';
			socket.poll(50);
		}
	} catch (e) {
		if (readfile(directory + '/cancel') != null) { terminal = 'cancelled'; reason = 'user_cancelled'; }
		else if (monotonic() >= job.deadline - 10) { terminal = 'incomplete'; reason = 'deadline'; }
		else { terminal = 'failed'; reason = 'worker_method_error'; }
	}
	job.metrics = { elapsed: monotonic() - job.started_at, memory_peak_bytes: readfile(groupPath(job.job_id) + '/memory.peak') };
	// The kernel group kills every descendant, even after a crashed node leader.
	let cleaned = cleanGroup(job.job_id);
	for (let task in active) { stopOwned(task.child); releaseSlots(task.slots); }
	if (engine != null && engine.handle != null) stopOwned(engine);
	if (!cleaned) { terminal = 'failed'; reason = 'cleanup_failed'; }
	if (terminal != 'completed')
		for (let row in job.rows)
			if (row.state == 'checking' || row.state == 'unknown' || row.phase != null) { row.state = terminal; row.phase = null; }
	if (terminal == 'completed') reason = null;
	finishJob(job, terminal, reason);
}
export { runJob };
