// Only original LAN tuples, including the optional extended IPv4 family prefix.
import { readfile } from 'fs';
import { matchRule } from '../lib/corporate.uc';
function returnedMatch(rules, policies, ip, port) {
	let rule = matchRule(rules, ip, port, 'tcp');
	return rule != null && policies[rule.id] != null && policies[rule.id].reset === true;
}
function originalTuple(line) {
	let fields = split(trim(line), /[[:space:]]+/);
	let protocol = fields[0] == 'ipv4' ? fields[2] : fields[0];
	if (protocol != 'tcp' && protocol != 'udp') return null;
	let tuple = match(line, / src=([0-9.]+) dst=([0-9.]+) sport=([0-9]+) dport=([0-9]+)/);
	return tuple == null ? null : { protocol: protocol, source: tuple[1], destination: tuple[2], sport: int(tuple[3]), dport: int(tuple[4]) };
}
function resetReturnedFlows(sh, rules, policies, lan, control) {
	control = control || {};
	function now() { return +split(readfile('/proc/uptime'), ' ')[0]; }
	let deadline = control.deadline || now() + 1.5;
	let required = false;
	for (let rule in rules) if (policies[rule.id] != null && policies[rule.id].reset) required = true;
	if (!required) return { state: 'not_needed' };
	if (now() >= deadline) return { state: 'failed', reason: 'conntrack_budget' };
	let command = 'timeout 0.4 conntrack -L -f ipv4 -o extended 2>/dev/null';
	let listed = sh.runBounded != null ? sh.runBounded(command, 1048576) : sh.runCapture(command);
	if (!listed.ok) return { state: 'failed', reason: 'conntrack_list_failed' };
	let failures = 0, deleted = 0, routes = {};
	for (let line in split(listed.out, '\n')) {
		if (now() >= deadline) return { state: 'failed', reason: 'conntrack_budget', deleted: deleted };
		let tuple = originalTuple(line);
		if (tuple == null || !returnedMatch(rules, policies, tuple.destination, tuple.dport)) continue;
		let route = routes[tuple.source];
		if (route == null) route = routes[tuple.source] = sh.runCapture('timeout 0.2 ip -4 route get ' + sh.shq(tuple.source) + ' 2>/dev/null');
		if (!route.ok) return { state: 'failed', reason: 'route_lookup_failed', deleted: deleted };
		if (index(split(trim(route.out), /[[:space:]]+/), lan) < 0) continue;
		let deletion = 'timeout 0.15 conntrack -D -f ipv4 -p ' + tuple.protocol + ' --orig-src ' + sh.shq(tuple.source) +
			' --orig-dst ' + sh.shq(tuple.destination) + ' --sport ' + tuple.sport + ' --dport ' + tuple.dport + ' 2>/dev/null';
		let result = control.execute != null ? control.execute(deletion) : sh.runCapture(deletion);
		if (result.obsolete) return { state: 'failed', reason: 'reset_obsolete', deleted: deleted };
		if (result.ok) deleted++; else failures++;
	}
	return { state: failures ? 'failed' : 'completed', deleted: deleted, failures: failures };
}
export { returnedMatch, originalTuple, resetReturnedFlows };
