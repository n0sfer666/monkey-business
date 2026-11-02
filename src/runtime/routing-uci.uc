import { CONFIG } from './paths.uc';
import { normalizeRouting } from '../lib/corporate.uc';

function readRouting(cursor) {
	let global = cursor.get_all(CONFIG, 'global') || {};
	let corporate = [];
	cursor.foreach(CONFIG, 'corporate_tunnel', function(section) {
		push(corporate, { id: section['.name'], name: section.name,
			enabled: section.enabled, requires_udp: section.requires_udp,
			address: section.address, port: section.port });
	});
	let result = normalizeRouting({ mode: global.routing_mode || 'bypass-local',
		region: global.local_region || 'ru', direct: global.custom_direct || '',
		proxy: global.custom_proxy || '', corporate_rules: corporate });
	if (length(result.errors)) return { error: 'invalid_stored_routing', items: result.errors };
	return { candidate: result.candidate };
}
function writeRouting(cursor, candidate) {
	cursor.set(CONFIG, 'global', 'routing_mode', candidate.mode);
	cursor.set(CONFIG, 'global', 'local_region', candidate.region);
	cursor.set(CONFIG, 'global', 'custom_direct', candidate.direct);
	cursor.set(CONFIG, 'global', 'custom_proxy', candidate.proxy);
	let old = [];
	cursor.foreach(CONFIG, 'corporate_tunnel', function(section) { push(old, section['.name']); });
	for (let id in old) cursor.delete(CONFIG, id);
	for (let rule in candidate.corporate_rules) {
		// A corporate ID must not replace an unrelated named section.
		if (cursor.get(CONFIG, rule.id) != null) return 'section_id_conflict';
		cursor.set(CONFIG, rule.id, 'corporate_tunnel');
		for (let key in ['name', 'enabled', 'requires_udp', 'address', 'port'])
			cursor.set(CONFIG, rule.id, key, '' + rule[key]);
	}
	return cursor.commit(CONFIG) === true ? null : 'uci_commit_failed';
}
function withRouting(applied, candidate) {
	let config = json(sprintf('%J', applied));
	config.global.routing_mode = candidate.mode;
	config.global.local_region = candidate.region;
	config.global.custom_direct = candidate.direct;
	config.global.custom_proxy = candidate.proxy;
	config.corporate_rules = candidate.corporate_rules;
	return config;
}
export { readRouting, writeRouting, withRouting };
