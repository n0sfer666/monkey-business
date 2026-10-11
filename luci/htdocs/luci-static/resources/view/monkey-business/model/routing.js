'use strict';
'require baseclass';

var MODES = [
	{ value: 'bypass-local', label: _('Bypass local') },
	{ value: 'gfwlist', label: _('Only blocked via VPN') },
	{ value: 'global', label: _('Everything via VPN') }
];

var REGIONS = [
	{ value: 'ru', label: _('Russia') },
	{ value: 'cn', label: _('China') },
	{ value: 'ir', label: _('Iran') },
	{ value: 'other', label: _('Other') }
];

function chips(mode, region) {
	var local = region !== 'other';
	var geo = mode === 'bypass-local' && local;
	var out = [];
	if (geo)
		out.push(_('geoip:%s direct').format(region));
	if (geo && region === 'ru')
		out.push(_('kernel bypass'));
	if (mode === 'gfwlist')
		out.push(region === 'cn' ? _('geosite:gfw via VPN') : _('only your Via VPN list'));
	if (mode === 'global')
		out.push(_('everything via VPN'));
	if (local)
		out.push(_('DNS %s direct, rest DoH').format(region));
	return out;
}

function count(rules) {
	var text = Array.isArray(rules) ? rules.join('\n') : String(rules || '');
	return text.replace(/,/g, '\n').split('\n').filter(function(line) {
		var t = line.trim();
		return t !== '' && t.charAt(0) !== '#';
	}).length;
}

return baseclass.extend({
	MODES: MODES,
	REGIONS: REGIONS,
	chips: chips,
	count: count
});
