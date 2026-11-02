// Protected tmpfs queue. The persistent procd worker owns all engine/job cleanup.
import { mkdir, unlink, rmdir, lsdir, readfile, open } from 'fs';
import { nonce, privateDirectory, privateJson, atomicPrivate } from './private-store.uc';
import { jobId, terminal, scope, start, status as publicStatus } from '../lib/availability-job.uc';
import { serverRef } from '../lib/availability.uc';
import { processIdentity } from './listener.uc';
import { cleanOwnedDirectory } from './owned-process.uc';
import { cleanGroup } from './engine-group.uc';
import { monotonic } from './routing-v2.uc';

const ROOT = '/tmp/mb-runtime/jobs';
function boot() { return trim(readfile('/proc/sys/kernel/random/boot_id')); }
function jobPath(id) { return jobId(id) ? ROOT + '/' + id : null; }
function loadIndex() {
	let value = privateJson(ROOT + '/index.json', 16384);
	return type(value) == 'array' ? value : [];
}
function readJob(id) {
	let path = jobPath(id);
	return path != null ? privateJson(path + '/status.json', 1048576) : null;
}
function writeJob(job) {
	let path = jobPath(job.job_id);
	return path != null && atomicPrivate(path + '/status.json', sprintf('%J', job));
}
function removeJob(id) {
	let path = jobPath(id);
	if (path == null) return false;
	for (let file in (lsdir(path) || [])) unlink(path + '/' + file);
	return rmdir(path);
}
function withQueue(fn) {
	if (!privateDirectory('/tmp/mb-runtime') || !privateDirectory(ROOT)) return { error: 'unsafe_job_directory' };
	let lock = open(ROOT + '/queue.lock', 'ae', 0o600);
	if (lock == null) return { error: 'job_lock_failed' };
	if (!lock.lock('xn')) { lock.close(); return { error: 'busy' }; }
	let result;
	try { result = fn(); } catch (e) { result = { error: 'job_storage_failed' }; }
	lock.close();
	return result;
}
function currentJob() {
	for (let item in loadIndex()) {
		let job = readJob(item.id);
		if (job != null && (!terminal(job.state) || !job.cleanup_done)) return job;
	}
	return null;
}
function enqueue(servers, args, method, network) {
	return withQueue(function() {
		let current = currentJob();
		if (current != null) return { api_version: 2, job_id: current.job_id, scope: current.scope, busy: true };
		let selected = scope(servers, args);
		if (selected.error != null) return selected;
		let index = [];
		for (let item in loadIndex()) {
			let cached = readJob(item.id);
			if (cached != null && cached.boot == boot() && cached.finished_at != null && monotonic() >= cached.finished_at && monotonic() - cached.finished_at < 600)
				push(index, item);
			else removeJob(item.id);
		}
		while (length(index) >= 4) { let old = shift(index); removeJob(old.id); }
		let id = nonce(), path = jobPath(id);
		if (!privateDirectory(path)) return { error: 'job_directory_failed' };
		let rows = map(selected.servers, function(server) {
			return { server_ref: serverRef(server), name: server.tag, state: 'unknown', udp: { state: 'not_checked' } };
		});
		let job = start(id, rows, monotonic(), boot());
		job.scope = args.scope; job.cleanup_done = false;
		let definition = { servers: selected.servers, method: method, network: network, boot: boot() };
		if (length(sprintf('%J', definition)) > 4194304 ||
			!atomicPrivate(path + '/definition.json', sprintf('%J', definition)) || !writeJob(job)) {
			removeJob(id); return { error: 'job_write_failed' };
		}
		push(index, { id: id });
		if (!atomicPrivate(ROOT + '/index.json', sprintf('%J', index))) { removeJob(id); return { error: 'job_index_failed' }; }
		return { api_version: 2, job_id: id, state: 'queued', total: job.total };
	});
}
function jobStatus(args) {
	let job = args != null && jobId(args.job_id) ? readJob(args.job_id) : null;
	if (job != null && !terminal(job.state) && job.worker != null &&
		processIdentity(job.worker.pid) != job.worker.identity) {
		job.state = 'failed'; job.reason = 'worker_crash';
	}
	return publicStatus(job, args, monotonic(), boot());
}
function cancelJob(args) {
	if (args == null || !jobId(args.job_id)) return { error: 'invalid_job_id' };
	return withQueue(function() {
		let job = readJob(args.job_id);
		if (job == null || job.boot != boot()) return { error: 'unknown_job' };
		if (terminal(job.state)) return { api_version: 2, job_id: job.job_id, state: job.state };
		if (!atomicPrivate(jobPath(job.job_id) + '/cancel', 'cancel')) return { error: 'cancel_failed' };
		return { api_version: 2, job_id: job.job_id, state: 'cancelling' };
	});
}
function finishJob(job, state, reason) {
	let cleaned = cleanGroup(job.job_id);
	if (!cleanOwnedDirectory(jobPath(job.job_id))) cleaned = false;
	job.state = cleaned ? state : 'failed'; job.reason = cleaned ? reason : 'cleanup_failed';
	job.cleanup_done = cleaned; job.finished_at = monotonic();
	return writeJob(job);
}
function reapOrphans() {
	if (!privateDirectory('/tmp/mb-runtime') || !privateDirectory(ROOT)) return;
	for (let name in (lsdir(ROOT) || [])) {
		if (match(name, /^[a-f0-9]{32}$/) == null || readJob(name) != null) continue;
		let path = jobPath(name), owner = privateJson(path + '/owner.json', 4096);
		if (owner != null && owner.active && processIdentity(owner.pid) == owner.identity) continue;
		if (cleanGroup(name) && cleanOwnedDirectory(path)) removeJob(name);
	}
}

export { ROOT, jobPath, readJob, writeJob, loadIndex, currentJob, enqueue, jobStatus, cancelJob, finishJob, boot, reapOrphans };
