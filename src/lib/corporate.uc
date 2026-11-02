// Общая граница доверия для RPC, UCI и генераторов. Невалидный off тоже ошибка.
import { validateRules } from './rules.uc';

const MODES = ['bypass-local', 'global', 'gfwlist'];
const REGIONS = ['ru', 'cn', 'ir', 'other'];

function publicIpv4(value, localAddresses) {
	if (type(value) != 'string' || match(value, /^(0|[1-9][0-9]{0,2})(\.(0|[1-9][0-9]{0,2})){3}$/) == null)
		return false;
	let octets = map(split(value, '.'), function(n) { return int(n); });
	for (let n in octets)
		if (n > 255) return false;
	let a = octets[0], b = octets[1], c = octets[2];
	// IANA special-purpose, private, documentation, benchmark and non-unicast.
	if (a == 0 || a == 10 || a == 127 || a >= 224 ||
		(a == 100 && b >= 64 && b <= 127) || (a == 169 && b == 254) ||
		(a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168) ||
		(a == 192 && b == 0 && (c == 0 || c == 2)) ||
		(a == 192 && b == 88 && c == 99) || (a == 198 && (b == 18 || b == 19)) ||
		(a == 198 && b == 51 && c == 100) || (a == 203 && b == 0 && c == 113))
		return false;
	return index(localAddresses || [], value) < 0;
}

function flag(value, fallback) {
	if (value == null) return fallback;
	if (value === 0 || value === '0' || value === false) return 0;
	if (value === 1 || value === '1' || value === true) return 1;
	return null;
}

function normalRule(raw, localAddresses) {
	let errors = [];
	if (type(raw) != 'object')
		return { errors: [{ field: 'rule', code: 'invalid_type' }] };
	let id = raw.id;
	if (type(id) != 'string' || match(id, /^[A-Za-z0-9_][A-Za-z0-9_-]{0,63}$/) == null)
		push(errors, { field: 'id', code: 'invalid_id' });
	let name = type(raw.name) == 'string' ? trim(raw.name) : '';
	// ucode length() counts bytes. uchr() is not needed: valid UTF-8 is checked explicitly
	// and only leading bytes count toward the agreed Unicode codepoint limit.
	let chars = 0, remaining = 0, low = 128, high = 191, utf8 = true;
	for (let i = 0; i < length(name); i++) {
		let n = ord(name, i);
		if (remaining > 0) {
			if (n < low || n > high) utf8 = false;
			remaining--; low = 128; high = 191;
		} else {
			chars++;
			if (n < 32 || n == 127) utf8 = false;
			else if (n >= 194 && n <= 223) remaining = 1;
			else if (n >= 224 && n <= 239) {
				remaining = 2;
				if (n == 224) low = 160;
				if (n == 237) high = 159;
			} else if (n >= 240 && n <= 244) {
				remaining = 3;
				if (n == 240) low = 144;
				if (n == 244) high = 143;
			} else if (n >= 128) utf8 = false;
			// C1 controls U+0080..009F are two-byte UTF-8 sequences.
			if (n == 194 && i + 1 < length(name) && ord(name, i + 1) < 160) utf8 = false;
		}
	}
	if (!utf8 || remaining || chars < 1 || chars > 64)
		push(errors, { field: 'name', code: 'invalid_name' });
	let enabled = flag(raw.enabled, 0), udp = flag(raw.requires_udp, 1);
	if (enabled == null) push(errors, { field: 'enabled', code: 'invalid_flag' });
	if (udp == null) push(errors, { field: 'requires_udp', code: 'invalid_flag' });
	if (!publicIpv4(raw.address, localAddresses))
		push(errors, { field: 'address', code: 'public_ipv4_required' });
	let port = raw.port == null ? '' : raw.port;
	if (type(port) == 'int') port = '' + port;
	if (type(port) != 'string' || (port != '' &&
		(match(port, /^[0-9]{1,5}$/) == null || int(port) < 1 || int(port) > 65535)))
		push(errors, { field: 'port', code: 'invalid_port' });
	if (length(errors)) return { errors: errors };
	return { rule: { id: id, name: name, address: raw.address,
		port: port == '' ? '' : '' + int(port), enabled: enabled, requires_udp: udp }, errors: [] };
}

function normalizeRules(raw, localAddresses) {
	if (type(raw) != 'array' || length(raw) > 32)
		return { errors: [{ field: 'corporate_rules', code: 'invalid_count' }] };
	let rules = [], errors = [], ids = {}, pairs = {};
	for (let i = 0; i < length(raw); i++) {
		let result = normalRule(raw[i], localAddresses);
		let id = type(raw[i]) == 'object' ? raw[i].id : null;
		if (type(id) != 'string' || match(id, /^[A-Za-z0-9_][A-Za-z0-9_-]{0,63}$/) == null) id = null;
		for (let error in result.errors)
			push(errors, { index: i, id: id,
				field: error.field, code: error.code });
		let rule = result.rule;
		if (rule == null) continue;
		let pair = rule.address + ':' + rule.port;
		if (exists(ids, rule.id)) push(errors, { id: rule.id, field: 'id', code: 'duplicate_id' });
		if (exists(pairs, pair)) push(errors, { id: rule.id, field: 'port', code: 'duplicate_pair' });
		ids[rule.id] = true; pairs[pair] = true;
		push(rules, rule);
	}
	return { rules: rules, errors: errors };
}

function normalizeRouting(candidate, localAddresses) {
	if (type(candidate) != 'object' || length(sprintf('%J', candidate)) > 131072)
		return { errors: [{ field: 'candidate', code: 'invalid_candidate' }] };
	let errors = [];
	for (let key in candidate)
		if (index(['mode', 'region', 'direct', 'proxy', 'corporate_rules'], key) < 0) {
			push(errors, { field: 'candidate', code: 'unexpected_field' });
			break;
		}
	if (index(MODES, candidate.mode) < 0) push(errors, { field: 'mode', code: 'invalid_mode' });
	if (index(REGIONS, candidate.region) < 0) push(errors, { field: 'region', code: 'invalid_region' });
	for (let key in ['direct', 'proxy'])
		if (type(candidate[key]) != 'string' || length(candidate[key]) > 65536)
			push(errors, { field: key, code: 'invalid_list' });
	if (!length(errors))
		for (let error in validateRules(candidate.direct, candidate.proxy))
			push(errors, { field: error.list, line: error.line, code: error.code });
	let corp = normalizeRules(candidate.corporate_rules, localAddresses);
	for (let error in corp.errors) push(errors, error);
	if (length(errors)) return { errors: errors };
	return { candidate: { mode: candidate.mode, region: candidate.region, direct: candidate.direct,
		proxy: candidate.proxy, corporate_rules: corp.rules }, errors: [] };
}

function orderedRules(rules) {
	let out = [];
	for (let rule in rules)
		if (rule.port != '') push(out, rule);
	for (let rule in rules)
		if (rule.port == '') push(out, rule);
	return out;
}

function matchRule(rules, address, port, protocol) {
	if (protocol != 'tcp' && protocol != 'udp') return null;
	let wildcard = null;
	for (let rule in rules) {
		if (rule.address != address) continue;
		if (rule.port == '' ) wildcard = rule;
		else if (int(rule.port) == port) return rule;
	}
	return wildcard;
}

export { publicIpv4, normalizeRules, normalizeRouting, orderedRules, matchRule };
