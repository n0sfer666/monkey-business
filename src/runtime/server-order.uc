// Scoped priority edits preserve every non-server section and inter-group position.
import { loadServers } from './uci.uc';
import { CONFIG } from './paths.uc';
import { outboundPayload } from '../lib/outbound.uc';
import { opaqueRevision } from './opaque-revision.uc';
import { fingerprint } from './fingerprint.uc';
import { atomicPrivate, privateJson } from './private-store.uc';
import { acquireMutation } from './mutation.uc';
import { serverRef, reorder } from '../lib/availability.uc';
import { request } from '../lib/routing-transaction.uc';
import { monotonic } from './routing-v2.uc';
function writePriority(cursor, servers, activeSub) {
	let names = {}, wanted = [], at = 0;
	for (let server in servers) names[server['.name']] = true;
	cursor.foreach(CONFIG, null, function(section) {
		push(wanted, names[section['.name']] ? servers[at++]['.name'] : section['.name']);
	});
	if (at != length(servers)) return 'server_set_conflict';
	for (let i = 0; i < length(wanted); i++)
		if (!cursor.reorder(CONFIG, wanted[i], i)) return 'order_write_failed';
	if (activeSub != null) cursor.set(CONFIG, 'global', 'active_sub', activeSub);
	return cursor.commit(CONFIG) === true ? null : 'order_commit_failed';
}
function serverOrder(freshCursor) {
	function snapshot() {
		let servers = loadServers(freshCursor()), groups = {}, list = [];
		for (let server in servers) {
			let ref = serverRef(server), key = sprintf('%J', [ref.source, ref.sub]);
			if (groups[key] == null) { groups[key] = []; push(list, groups[key]); }
			push(groups[key], ref);
		}
		return { api_version: 2, revision: opaqueRevision('server-order', map(servers, function(server) { return [serverRef(server), outboundPayload(server), server.disabled]; })), groups: list, servers: servers };
	}
	function get() { let s = snapshot(); let checked = reorder(s.servers, s.groups); if (checked.error != null) return { api_version: 2, error: checked.error }; delete s.servers; return s; }
	function install(servers) { return writePriority(freshCursor(), servers, null); }
	function apply(args) {
		let invalid = request(args);
		if (invalid != null) return invalid;
		let lock = acquireMutation();
		if (lock == null) return { error: 'busy' };
		let result, before = null, installed = false;
		try {
			let body = fingerprint([args.expected_revision, args.groups]), cache = privateJson('/tmp/mb-runtime/order-requests.json', 65536) || [];
			cache = filter(cache, function(item) { return monotonic() - item.created < 600; });
			let cached = null;
			for (let item in cache) if (item.id == args.request_id) cached = item;
			before = snapshot();
			if (cached != null) result = cached.body == body ? cached.result : { error: 'request_id_reused' };
			else if (before.revision != args.expected_revision) result = { error: 'revision_conflict' };
			else {
				let ordered = reorder(before.servers, args.groups);
				if (ordered.error != null) result = ordered;
				else {
					let nextRevision = opaqueRevision('server-order', map(ordered.servers, function(server) { return [serverRef(server), outboundPayload(server), server.disabled]; }));
					let error = install(ordered.servers); installed = error == null;
					if (error != null) result = { error: install(before.servers) == null ? error : 'rollback_failed' };
					else result = { api_version: 2, ok: true, status: 'saved_order', revision: nextRevision };
					push(cache, { id: args.request_id, body: body, result: result, created: monotonic() });
					while (length(cache) > 16) shift(cache);
					if (!atomicPrivate('/tmp/mb-runtime/order-requests.json', sprintf('%J', cache))) {
						result = { error: install(before.servers) == null ? 'request_cache_failed' : 'rollback_failed' };
						installed = false;
					}
				}
			}
		} catch (e) { result = { error: installed && before != null && install(before.servers) != null ? 'rollback_failed' : 'order_apply_failed' }; }
		lock.close(); return result;
	}
	return { get: get, apply: apply };
}
export { serverOrder, writePriority };
