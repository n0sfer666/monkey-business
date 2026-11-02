// Единственная чистая машина состояний для observer, recovery и corporate policy.
// now — монотонные секунды в текущей загрузке. Публикация только после установки nft.

function signal() {
	return { state: 'unknown', successes: 0, failures: 0, sample: 'unknown' };
}

function advance(previous, sample) {
	let out = { state: previous.state, successes: 0, failures: 0, sample: sample };
	if (sample == 'success') {
		out.successes = min(previous.successes + 1, 2);
		if (out.successes == 2) out.state = 'up';
	} else if (sample == 'failure') {
		out.failures = min(previous.failures + 1, 2);
		if (out.failures == 2) out.state = 'down';
	} else out.sample = 'unknown';
	return out;
}

function validContext(context) {
	if (type(context) != 'object') return false;
	for (let key in ['boot', 'outbound', 'runtime', 'method', 'network'])
		if (type(context[key]) != 'string' || !length(context[key]) || length(context[key]) > 128) return false;
	return true;
}

function sameContext(a, b) {
	return validContext(a) && validContext(b) && a.outbound == b.outbound && a.runtime == b.runtime &&
		a.method == b.method && a.network == b.network && a.boot == b.boot;
}

function initial(context) {
	return { context: context, https: signal(), udp: signal(), measured: null };
}

function round(previous, context, https, udp, now) {
	// Пробы старого контекста нельзя зачислять новой generation даже после reload.
	if (!sameContext(previous.context, context)) return { error: 'obsolete_round' };
	return { context: context, https: advance(previous.https, https),
		udp: advance(previous.udp, udp), measured: now };
}

function rebase(previous, context) {
	// Сохраняется applied policy, не старый диагноз для новых целей/WAN/runtime.
	return initial(context);
}

function fresh(health, now) {
	return type(health) == 'object' && validContext(health.context) &&
		health.measured != null && now >= health.measured && now - health.measured <= 45;
}

function effective(rule, previous, health, enabled, now) {
	// Ошибка снимка не даёт права менять уже установленную ядерную политику.
	if (type(health) != 'object' || !validContext(health.context)) return { error: 'invalid_context' };
	let compatible = validContext(health.context) && previous != null && previous.id == rule.id &&
		previous.boot == health.context.boot && previous.outbound == health.context.outbound;
	let out = { id: rule.id, boot: health.context.boot, outbound: health.context.outbound,
		route: compatible && previous.route == 'proxy' ? 'proxy' : 'direct',
		last_return: compatible ? previous.last_return : null, reset: false };
	if (!enabled || !rule.enabled) {
		out.route = 'direct'; out.reason = enabled ? 'rule_off' : 'vpn_off';
		return out;
	}
	if (!fresh(health, now)) {
		out.reason = health.measured == null ? 'awaiting_health' : 'stale_monitor'; return out;
	}
	let required = [health.https];
	if (rule.requires_udp) push(required, health.udp);
	// Подтверждённая причина имеет приоритет над unknown/ошибкой другого сигнала.
	for (let item in required)
		if (item.state == 'down') {
			out.route = 'direct';
			out.reason = health.https.state == 'down' ? 'https_down' : 'udp_down';
			return out;
		}
	for (let item in required)
		if (item.sample != 'success' || item.state != 'up' || item.successes < 2) {
			out.reason = 'awaiting_health'; return out;
		}
	if (out.route == 'proxy') { out.reason = 'healthy'; return out; }
	if (out.last_return != null && now - out.last_return < 60) {
		out.reason = 'return_cooldown'; return out;
	}
	out.route = 'proxy'; out.reason = 'healthy'; out.last_return = now; out.reset = true;
	return out;
}

// Успех одной цели достаточен. Внутренняя ошибка без успеха — не сетевой failure.
function aggregate(targets) {
	let failures = 0;
	for (let target in targets) {
		if (target.state == 'success') return 'success';
		if (target.state == 'failure') failures++;
	}
	return length(targets) == 2 && failures == 2 ? 'failure' : 'unknown';
}

export { initial, advance, validContext, sameContext, round, rebase, fresh, effective, aggregate };
