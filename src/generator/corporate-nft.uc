// Only validated IPv4/decimal ports reach nft syntax. No names or user IDs are emitted.
import { normalizeRules } from '../lib/corporate.uc';

const SETS = ['corp_exact_direct', 'corp_exact_proxy', 'corp_wild_direct', 'corp_wild_proxy'];
function elements(rules, policies) {
	let checked = normalizeRules(rules);
	if (length(checked.errors)) die('invalid_corporate_rules');
	let out = {};
	for (let name in SETS) out[name] = [];
	for (let rule in checked.rules) {
		let route = policies[rule.id] != null ? policies[rule.id].route : 'direct';
		if (route != 'direct' && route != 'proxy') die('invalid_corporate_policy');
		// Off can never be forced into proxy by stale effective state.
		if (!rule.enabled) route = 'direct';
		let exact = rule.port != '';
		push(out['corp_' + (exact ? 'exact_' : 'wild_') + route],
			rule.address + (exact ? ' . ' + rule.port : ''));
	}
	return out;
}
function declarations(rules, policies) {
	let values = elements(rules, policies), out = '';
	for (let name in SETS) {
		let exact = index(name, 'exact') >= 0;
		out += '\n set ' + name + ' { type ' + (exact ? 'ipv4_addr . inet_service' : 'ipv4_addr') + ';';
		if (length(values[name])) out += ' elements = { ' + join(', ', values[name]) + ' };';
		out += ' }';
	}
	return out;
}
function update(rules, policies) {
	let values = elements(rules, policies), out = '';
	for (let name in SETS) {
		out += 'flush set inet monkey_business ' + name + '\n';
		if (length(values[name])) out += 'add element inet monkey_business ' + name +
			' { ' + join(', ', values[name]) + ' }\n';
	}
	return out;
}
export { declarations, update, elements };
