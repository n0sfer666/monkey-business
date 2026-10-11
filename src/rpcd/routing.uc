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
	let items = validateRules(l.direct, l.proxy);
	if (length(items))
		return { error: "invalid_rules", items: items };
	ctx.setCustomRouting(l.direct, l.proxy);
	return configApply(ctx);
}

export { routingCheck, setRouting };
