// Manual ranking не разделяет timestamp/cache purpose с активным observer.
import { serverSub } from './subs.uc';

function serverRef(server) {
	let sub = serverSub(server);
	return sub == null ? { source: 'manual', tag: server.tag } :
		{ source: 'subscription', sub: sub, tag: server.tag };
}

function refKey(ref) {
	if (type(ref) != 'object' || type(ref.tag) != 'string' || length(ref.tag) < 1 || length(ref.tag) > 256)
		return null;
	if (ref.source == 'manual' && ref.sub == null)
		return sprintf('%J', ['manual', ref.tag]);
	if (ref.source == 'subscription' && type(ref.sub) == 'string' && length(ref.sub) > 0 && length(ref.sub) <= 64)
		return sprintf('%J', ['subscription', ref.sub, ref.tag]);
	return null;
}

function resolveRef(servers, ref) {
	let key = refKey(ref), found = null;
	if (key == null) return { error: 'invalid_ref' };
	for (let server in servers)
		if (refKey(serverRef(server)) == key) {
			if (found != null) return { error: 'identity_conflict' };
			found = server;
		}
	return found == null ? { error: 'unknown_server' } : { server: found };
}

function summarize(base, extra) {
	let successes = 0, latency = 0, methodError = null;
	for (let target in base) {
		if (target.state == 'success') { successes++; latency += target.latency_ms; }
		else if (target.state != 'failure') methodError = target.state;
	}
	if (extra != null && extra.state != 'success' && extra.state != 'failure') methodError = extra.state;
	let state = 'probe_failed';
	if (successes == 2) state = extra != null && extra.state == 'failure' ? 'degraded' : 'available';
	else if (successes == 1) state = 'degraded';
	if (methodError != null) state = methodError;
	if (length(base) != 2) state = 'incomplete';
	return { state: state, attempts: 2, successes: successes,
		latency_ms: successes ? latency / (successes * 1.0) : null,
		extra_failed: extra != null && extra.state == 'failure' };
}

function complete(record) {
 return record != null && record.phase == null && record.base_finished != null &&
  index(['checking', 'unknown', 'cancelled', 'incomplete', 'failed'], record.state) < 0;
}
function fresh(record, context, now) {
	if (type(context) != 'object') return false;
	for (let key in ['fingerprint', 'method', 'network', 'boot'])
		if (type(context[key]) != 'string' || !length(context[key])) return false;
	return complete(record) && record.purpose == 'manual' && record.base_finished != null &&
		now >= record.base_finished && now - record.base_finished < 300 &&
		record.fingerprint == context.fingerprint && record.method == context.method &&
		record.network == context.network && record.boot == context.boot;
}

function compare(a, b) {
	let classes = { available: 0, degraded: 1, probe_failed: 2 };
	let ac = classes[a.state], bc = classes[b.state];
	if (!a.fresh || ac == null) ac = 3;
	if (!b.fresh || bc == null) bc = 3;
	if (ac != bc) return ac - bc;
	if (ac == 3) return a.order - b.order;
	if (a.successes != b.successes) return b.successes - a.successes;
	if (a.latency_ms != b.latency_ms) return a.latency_ms - b.latency_ms;
	return a.order - b.order;
}

// Перестановка только в исходных позициях группы: interleaving соседей сохраняется.
function reorder(servers, groups) {
	if (type(groups) != 'array') return { error: 'invalid_groups' };
	let members = {}, seen = {}, output = [];
	for (let server in servers) {
		let key = refKey(serverRef(server));
		if (key == null || exists(members, key)) return { error: 'identity_conflict' };
		members[key] = server;
	}
	let positions = {};
	for (let group in groups) {
		if (type(group) != 'array' || !length(group)) return { error: 'invalid_group' };
		let source = null, refs = [];
		for (let ref in group) {
			let key = refKey(ref);
			if (key == null || !exists(members, key) || exists(seen, key)) return { error: 'invalid_permutation' };
			let owner = sprintf('%J', [ref.source, ref.sub]);
			if (source != null && source != owner) return { error: 'mixed_group' };
			source = owner; seen[key] = true; push(refs, members[key]);
		}
		if (exists(positions, source)) return { error: 'duplicate_group' };
		positions[source] = { servers: refs, next: 0 };
	}
	if (length(keys(seen)) != length(servers)) return { error: 'incomplete_permutation' };
	for (let server in servers) {
		let ref = serverRef(server), owner = sprintf('%J', [ref.source, ref.sub]);
		let position = positions[owner];
		push(output, position.servers[position.next++]);
	}
	return { servers: output };
}

export { serverRef, refKey, resolveRef, summarize, complete, fresh, compare, reorder };
