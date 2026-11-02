// Transaction coordinator; preparation may be slow, installation is serialized.
// All reads in this module refer to committed scoped state, never LuCI staging.
import { normalizeRouting } from './corporate.uc';

function request(args) {
	if (type(args) != 'object' || type(args.request_id) != 'string' ||
		match(args.request_id, /^[A-Za-z0-9_-]{16,64}$/) == null ||
		type(args.expected_revision) != 'string' || length(args.expected_revision) > 128)
		return { error: 'invalid_request' };
	return null;
}

function fence(a, b) {
	return a.revision == b.revision && a.generation == b.generation && a.runtime == b.runtime &&
		sprintf('%J', a.intent) == sprintf('%J', b.intent) && a.enabled == b.enabled;
}

function applyRouting(ctx, args) {
	let invalid = request(args);
	if (invalid != null) return invalid;
	let addresses;
	try { addresses = ctx.localAddresses(); } catch (e) { return { error: 'interface_query_failed' }; }
	let normalized = normalizeRouting(args.candidate, addresses);
	if (length(normalized.errors)) return { error: 'invalid_candidate', items: normalized.errors };
	let candidate = normalized.candidate;
	let body = ctx.requestBody ? ctx.requestBody([args.expected_revision, candidate]) : sprintf('%J', [args.expected_revision, candidate]);
	let cached = ctx.requestResult(args.request_id);
	if (cached != null)
		return cached.body == body ? cached.result : { error: 'request_id_reused' };
	let before = ctx.routingSnapshot();
	if (before.error != null) return { error: before.error };
	if (before.revision != args.expected_revision) return { error: 'revision_conflict' };
	if (before.enabled && before.outbound == null) return { error: 'applied_outbound_missing' };
	// Includes offline Xray/nft validation. No writes to committed configuration.
	let prepared;
	try { prepared = ctx.prepareRouting(candidate, before); }
	catch (e) { return { error: 'preparation_failed' }; }
	if (prepared.error != null) { ctx.discardRouting(prepared); return { error: prepared.error }; }
	if (!ctx.lockMutation()) { ctx.discardRouting(prepared); return { error: 'busy' }; }
	let result;
	function failed(cause) {
		let restored = 'restore_failed';
		try { restored = ctx.restoreRouting(before); } catch (e) {}
		let failure = { error: restored == null ? 'apply_failed' : 'rollback_failed', cause: cause };
		try { ctx.recordRequest(args.request_id, body, failure); }
		catch (e) { return { error: 'rollback_failed', cause: 'request_cache_failed' }; }
		if (restored == null && ctx.finishRouting != null && ctx.finishRouting(before) != null) {
			failure = { error: 'rollback_failed', cause: 'transition_release_failed' };
			try { ctx.recordRequest(args.request_id, body, failure); } catch (e) {}
		}
		return failure;
	}
	try {
		// Recheck idempotency inside the lock: two RPC requests may prepare together.
		cached = ctx.requestResult(args.request_id);
		let current = ctx.routingSnapshot();
		if (cached != null)
			result = cached.body == body ? cached.result : { error: 'request_id_reused' };
		else if (!fence(before, current)) result = { error: 'runtime_conflict' };
		else {
			let err = ctx.installRouting(prepared, before);
			if (err == null) err = ctx.verifyRouting(prepared, before);
			if (err == null) err = ctx.commitRouting(candidate);
			if (err == null) err = ctx.publishRouting(prepared, before);
			if (err != null) result = failed(err);
			else {
				result = { ok: true, status: before.enabled ? 'applied' : 'saved_disabled', revision: ctx.routingSnapshot().revision };
				ctx.recordRequest(args.request_id, body, result);
				if (ctx.finishRouting != null) {
					err = ctx.finishRouting(before);
					if (err != null) result = failed(err);
				}
			}
		}
	} catch (e) { result = failed('internal_error'); }
	ctx.unlockMutation();
	ctx.discardRouting(prepared);
	return result;
}

export { request, fence, applyRouting };
