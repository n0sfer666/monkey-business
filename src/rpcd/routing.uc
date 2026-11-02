import { applyRouting } from "../lib/routing-transaction.uc";
import { validateRules } from "../lib/rules.uc";
import { configApply } from "./handlers.uc";

function lists(args) {
	return {
		direct: (args != null && args.direct != null) ? "" + args.direct : "",
		proxy: (args != null && args.proxy != null) ? "" + args.proxy : "",
	};
}

function routingCheck(args) {
	let l = lists(args);
	return { items: validateRules(l.direct, l.proxy) };
}

function setRouting(ctx, args) {
	let l = lists(args);
	if (ctx.routingSnapshot != null) {
		let snapshot = ctx.routingSnapshot();
		if (snapshot.error != null) return { error: snapshot.error };
		let candidate = snapshot.candidate;
		candidate.direct = l.direct; candidate.proxy = l.proxy;
		return applyRouting(ctx, { expected_revision: snapshot.revision,
			request_id: 'legacy_' + ctx.randomHex() + ctx.randomHex(), candidate: candidate });
	}
	let items = validateRules(l.direct, l.proxy);
	if (length(items))
		return { error: "invalid_rules", items: items };
	let g = ctx.getGlobal();
	let prev = { direct: g.custom_direct || "", proxy: g.custom_proxy || "" };
	ctx.setCustomRouting(l.direct, l.proxy);
	let res = configApply(ctx);
	if (res.error != null)
		ctx.setCustomRouting(prev.direct, prev.proxy);
	return res;
}

export { routingCheck, setRouting };
