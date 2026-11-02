import { serverRef, refKey, resolveRef } from './availability.uc';
import { serverSub } from './subs.uc';

function jobId(value) {
	return type(value) == 'string' && match(value, /^[A-Za-z0-9_-]{1,64}$/) != null;
}
function page(args) {
	if (type(args) != 'object' || !jobId(args.job_id) || type(args.offset) != 'int' || args.offset < 0 ||
		type(args.limit) != 'int' || args.limit < 1 || args.limit > 50)
		return { error: 'invalid_page' };
	return { offset: args.offset, limit: args.limit };
}
function scope(servers, args) {
	if (type(args) != 'object' || index(['all', 'subscription', 'server'], args.scope) < 0)
		return { error: 'invalid_scope' };
	let selected = servers;
	if (args.scope == 'subscription') {
		if (type(args.sub) != 'string' || !length(args.sub) || length(args.sub) > 64)
			return { error: 'invalid_subscription' };
		selected = filter(servers, function(server) { return serverSub(server) == args.sub; });
	} else if (args.scope == 'server') {
		let result = resolveRef(servers, args.server_ref);
		if (result.error != null) return result;
		selected = [result.server];
	}
	if (length(selected) > 200) return { error: 'scope_too_large', max: 200 };
	if (!length(selected)) return { error: 'empty_scope' };
	let seen = {};
	for (let server in selected) {
		let key = refKey(serverRef(server));
		if (key == null || exists(seen, key)) return { error: 'identity_conflict' };
		seen[key] = true;
	}
	return { servers: selected };
}
function start(id, rows, now, boot) {
	if (!jobId(id) || type(rows) != 'array' || !length(rows) || length(rows) > 200) return { error: 'invalid_job' };
	return { api_version: 2, job_id: id, state: 'queued', reason: null, boot: boot,
		started_at: now, deadline: now + 240, total: length(rows), completed: 0, rows: rows };
}
function terminal(state) { return index(['completed', 'cancelled', 'incomplete', 'failed'], state) >= 0; }
function outcomeCounts(rows) {
	let counts = {};
	for (let row in rows) {
		let state = row.state || 'unknown';
		counts[state] = (counts[state] || 0) + 1;
	}
	return counts;
}
function publicRow(row) {
	// Allowlist: worker configs, fingerprints and endpoint URLs cannot cross read ACL.
	return { server_ref: row.server_ref, name: type(row.name) == 'string' ? substr(row.name, 0, 256) : '',
		state: row.state, phase: row.phase, reason: row.reason, successes: row.successes, attempts: row.attempts,
		latency_ms: row.latency_ms, udp: row.udp, base_finished: row.base_finished,
		extra_failed: row.extra_failed };
}
function status(job, args, now, boot) {
	let pagination = page(args);
	if (pagination.error != null) return pagination;
	if (type(job) != 'object' || job.job_id != args.job_id || job.boot != boot) return { error: 'unknown_job' };
	let state = job.state, reason = job.reason;
	if (!terminal(state) && now >= job.deadline) { state = 'incomplete'; reason = 'deadline'; }
	let result = { api_version: 2, job_id: job.job_id, state: state, reason: reason,
		started_at: job.started_at, deadline: job.deadline, total: job.total, completed: job.completed, base_completed: job.base_completed,
		offset: pagination.offset, counts: outcomeCounts(job.rows),
		rows: map(slice(job.rows, pagination.offset, pagination.offset + pagination.limit), publicRow) };
	if (length(sprintf('%J', result)) > 131072) return { error: 'response_too_large', api_version: 2 };
	return result;
}
export { jobId, page, scope, start, terminal, outcomeCounts, publicRow, status };
