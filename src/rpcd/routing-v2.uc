import { normalizeRouting } from '../lib/corporate.uc';
import { applyRouting } from '../lib/routing-transaction.uc';

function routingGet(ctx) {
	let snapshot = ctx.routingSnapshot();
	if (snapshot.error != null) return { api_version: 2, error: snapshot.error };
	return { api_version: 2, candidate: snapshot.candidate, revision: snapshot.revision,
		generation: snapshot.generation, health: ctx.healthStatus ? ctx.healthStatus() : snapshot.health, effective_policy: snapshot.policies,
		enabled: snapshot.enabled, runtime_error: snapshot.runtime_error };
}
function routingValidate(ctx, args) {
	let addresses;
	try { addresses = ctx.localAddresses(); } catch (e) { return { api_version: 2, valid: false, items: [{ field: 'corporate_rules', code: 'interface_query_failed' }] }; }
	let result = normalizeRouting(args != null ? args.candidate : null, addresses);
	return { api_version: 2, valid: !length(result.errors), items: result.errors };
}
function routingApply(ctx, args) {
	let result = applyRouting(ctx, args);
	result.api_version = 2;
	return result;
}
export { routingGet, routingValidate, routingApply };
