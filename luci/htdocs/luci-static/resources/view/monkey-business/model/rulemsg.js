'use strict';
'require baseclass';

var MSG = {
	space: function() { return _('No spaces inside an entry'); },
	scheme: function(a) { return _('Remove the scheme: write %s').format(a); },
	geo_empty: function(a) { return _('Missing %s name after the colon').format(a); },
	geo_name: function(a) { return _('Invalid %s name').format(a); },
	slashes: function() { return _('Only one / allowed'); },
	ip4: function() { return _('Not a valid IPv4 address'); },
	ip6: function() { return _('Not a valid IPv6 address'); },
	mapped: function(a) { return _('IPv4-mapped address: write %s').format(a); },
	prefix: function(a) { return _('Prefix must be 0–%s').format(a); },
	path: function(a) { return _('Remove the path: write %s').format(a); },
	wildcard: function() { return _('Wildcard only as *. at the start'); },
	incomplete: function() { return _('Domain is incomplete'); },
	not_full: function(a) { return _('Not a full domain, e.g. %s.com').format(a); },
	chars: function() { return _('Invalid characters in domain'); },
	tld: function() { return _('Invalid top-level domain'); },
	port: function(a) { return _('Remove the port: write %s').format(a); },
	matcher_empty: function(a) { return _('Missing value after %s:').format(a); }
};

function text(item) {
	var f = MSG[item && item.code];
	return f ? f(String(item.arg == null ? '' : item.arg)) : _('Invalid entry');
}

function fixing(n) {
	return n === 1 ? _('1 line needs fixing') : _('%d lines need fixing').format(n);
}

function byList(items, list) {
	return (items || []).filter(function(i) { return i.list === list; });
}

function mobileFoot(total, other) {
	if (!total)
		return _('One per line: domain, *.domain, IP/CIDR, geosite:NAME, geoip:NAME. Split modes only.');
	return fixing(total) + (other ? ' · ' + _('%d on the other tab').format(other) : '') + ' — ' + _('fix to save');
}

return baseclass.extend({
	text: text,
	fixing: fixing,
	byList: byList,
	mobileFoot: mobileFoot
});
