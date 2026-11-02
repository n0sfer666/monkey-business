import { configApply } from "./handlers.uc";
import { serverSub, subId, findSub, activeSubId, subDeath, nextAlive } from "../lib/subs.uc";

function applySwitched(ctx, res, deadline) {
	let ap = configApply(ctx, { deadline: deadline });
	if (ap.error != null) {
		res.ok = false;
		res.error = ap.error;
		return res;
	}
	res.applied = ap.skipped == null;
	res.server_id = ap.server_id;
	return res;
}

function subscriptionAutoswitch(ctx, args) {
	let subs = ctx.getSubscriptions();
	let from = activeSubId(subs, ctx.getGlobal().active_sub);
	let now = ctx.now();
	let reason = (from != null) ? subDeath(findSub(subs, from), now) : null;
	if (reason == null)
		return { ok: true, active_sub: from };
	let to = nextAlive(subs, from, now);
	if (to == null)
		return { ok: true, active_sub: from, dead: reason };
	if (args != null && args.check == true)
		return { ok: true, active_sub: from, dead: reason, switch_to: subId(to) };
	let deadline = (args != null) ? int(args.deadline) : 0;
	if (deadline > 0 && now >= deadline)
		return { error: "deadline passed before subscription_autoswitch started" };
	let sel = ctx.getSelectedServer();
	if (!ctx.setActiveSub(subId(to)))
		return { error: "could not save the subscription choice (read-only config?)" };
	ctx.setAutoswitch(from, reason);
	let res = { ok: true, active_sub: subId(to), switched_from: from, reason: reason, applied: false };
	if (sel != null && serverSub(sel) != from)
		return res;
	return applySwitched(ctx, res, deadline);
}

export { subscriptionAutoswitch };
