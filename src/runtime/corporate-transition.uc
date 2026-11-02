// Freeze only corporate proxy tuples while the two routing engines are replaced.
import { unlink, lstat } from 'fs';
import { isTrue } from '../lib/val.uc';
import { elements } from '../generator/corporate-nft.uc';
import { atomicPrivate, privateDirectory, privateJson, nonce } from './private-store.uc';
const ROOT = '/tmp/mb-runtime', STATE = ROOT + '/corporate-transition.json';
function transitionDocument(scopes) {
	let out = 'table inet mb_corporate_transition\ndelete table inet mb_corporate_transition\ntable inet mb_corporate_transition {\n';
	for (let i = 0; i < length(scopes); i++) {
		let scope = scopes[i];
		if (type(scope.lan) != 'string' || match(scope.lan, /^[A-Za-z0-9_.-]{1,15}$/) == null) die('invalid_lan_interface');
		let values = elements(scope.rules, scope.policies);
		for (let kind in ['corp_exact_direct', 'corp_exact_proxy', 'corp_wild_proxy']) {
			let type_ = kind == 'corp_wild_proxy' ? 'ipv4_addr' : 'ipv4_addr . inet_service';
			out += 'set s' + i + '_' + kind + ' { type ' + type_ + ';';
			if (length(values[kind])) out += ' elements = { ' + join(', ', values[kind]) + ' };';
			out += ' }\n';
		}
		out += 'chain scope' + i + ' {\n' +
			'meta l4proto { tcp, udp } ip daddr . th dport @s' + i + '_corp_exact_direct return\n' +
			'meta l4proto { tcp, udp } ip daddr . th dport @s' + i + '_corp_exact_proxy counter drop\n' +
			'meta l4proto { tcp, udp } ip daddr @s' + i + '_corp_wild_proxy counter drop\n}\n';
	}
	out += 'chain prerouting { type filter hook prerouting priority -151; policy accept;\n';
	for (let i = 0; i < length(scopes); i++) out += 'iifname "' + scopes[i].lan + '" jump scope' + i + '\n';
	return out + '}\n}\n';
}
function beginTransition(sh, additions) {
	if (!privateDirectory(ROOT)) return 'unsafe_runtime_directory';
	let previous = privateJson(STATE, 262144), scopes = previous != null ? previous.scopes || [] : [];
	for (let scope in additions) {
		if (!length(scope.rules || [])) continue;
		let duplicate = false;
		for (let known in scopes) if (sprintf('%J', known) == sprintf('%J', scope)) duplicate = true;
		if (!duplicate) push(scopes, scope);
	}
	if (length(scopes) > 8) return 'transition_recovery_required';
	let prefix = ROOT + '/transition-' + nonce(), error = null;
	try {
		if (!atomicPrivate(prefix + '.nft', transitionDocument(scopes)) ||
			!atomicPrivate(prefix + '.json', sprintf('%J', { scopes: scopes }))) error = 'transition_preparation_failed';
		else if (!sh.runCapture('timeout 1 nft -f ' + prefix + '.nft').ok) error = 'transition_install_failed';
		else if (!atomicPrivate(STATE, sprintf('%J', { scopes: scopes }))) error = 'transition_snapshot_failed';
	} catch (e) { error = 'transition_preparation_failed'; }
	unlink(prefix + '.nft'); unlink(prefix + '.json');
	return error;
}
function endTransition(sh) {
	if (!privateDirectory(ROOT)) return 'unsafe_runtime_directory';
	let path = ROOT + '/transition-end-' + nonce() + '.nft';
	if (!atomicPrivate(path, 'table inet mb_corporate_transition\ndelete table inet mb_corporate_transition\n')) return 'transition_release_failed';
	let result = sh.runCapture('timeout 1 nft -f ' + path); unlink(path);
	if (!result.ok) return 'transition_release_failed';
	if (lstat(STATE) != null && !unlink(STATE)) return 'transition_release_failed';
	return null;
}
function scope(config, policies) {
	let rules = [], routes = {};
	for (let rule in config.corporate_rules || []) {
		push(rules, { id: rule.id, name: 'Transition', address: rule.address, port: rule.port || '', enabled: isTrue(rule.enabled), requires_udp: false });
		routes[rule.id] = { route: policies != null && policies[rule.id] != null ? policies[rule.id].route : 'direct' };
	}
	return { lan: config.global.lan_iface || 'br-lan', rules: rules, policies: routes };
}
export { transitionDocument, beginTransition, endTransition, scope };
