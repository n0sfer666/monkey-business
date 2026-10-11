'use strict';
'require baseclass';
'require view.monkey-business.subs as subs';

var FAST_MS = 100;
var BAR_MS = 200;
var ON = [ '1', 'true', 'yes', 'on' ];

function isOff(s) {
	return ON.indexOf(String(s.disabled)) >= 0;
}

function isManual(s) {
	return subs.serverSub(s) == null;
}

function endpoint(s) {
	var host = String(s.address || '');
	return (host.indexOf(':') >= 0 ? '[' + host + ']' : host) + ':' + (s.port || '');
}

function title(s) {
	return s.tag || endpoint(s);
}

function protocol(s) {
	if (s.protocol === 'hysteria2')
		return 'hysteria2';
	if (!s.security)
		return 'vless';
	return 'vless / ' + (s.security === 'none' ? _('no TLS') : s.security);
}

function visible(servers, subIds) {
	return servers.filter(function(s) {
		var id = subs.serverSub(s);
		return id == null || subIds.length === 0 || subIds.indexOf(id) >= 0;
	});
}

function filtered(servers, by) {
	if (by === 'all')
		return servers;
	return servers.filter(function(s) {
		return by === 'manual' ? isManual(s) : subs.serverSub(s) === by;
	});
}

function filters(servers, subList) {
	var out = [ { value: 'all', label: _('All') } ];
	subList.forEach(function(sub) {
		if (filtered(servers, sub.id).length)
			out.push({ value: sub.id, label: sub.name });
	});
	if (servers.some(isManual))
		out.push({ value: 'manual', label: _('Manual') });
	return out;
}

function pingOf(r) {
	return { ms: r.latency_ms != null ? r.latency_ms : null, na: !!(r.na || r.ping_na), off: !!r.auto_disabled };
}

function ping(p) {
	if (p == null)
		return { kind: 'none' };
	if (p.na)
		return { kind: 'na' };
	if (p.off)
		return { kind: 'off', ms: p.ms };
	if (p.ms == null)
		return { kind: 'none' };
	return {
		kind: p.ms <= FAST_MS ? 'fast' : 'slow',
		ms: p.ms,
		pct: Math.min(100, Math.round(p.ms / BAR_MS * 100))
	};
}

function rank(p) {
	return (p != null && !p.na && p.ms != null) ? p.ms : Infinity;
}

return baseclass.extend({
	isOff: isOff,
	isManual: isManual,
	endpoint: endpoint,
	title: title,
	protocol: protocol,
	visible: visible,
	filtered: filtered,
	filters: filters,
	pingOf: pingOf,
	ping: ping,
	rank: rank
});
