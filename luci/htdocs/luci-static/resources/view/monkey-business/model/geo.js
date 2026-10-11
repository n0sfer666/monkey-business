'use strict';
'require baseclass';

function size(bytes) {
	var n = parseFloat(bytes);
	return (isNaN(n) || n <= 0) ? _('missing') : (n / 1048576).toFixed(1) + ' MB';
}

function date(epoch) {
	var n = parseInt(epoch, 10);
	if (isNaN(n) || n <= 0)
		return '';
	var d = new Date(n * 1000);
	return [ d.getFullYear(), d.getMonth() + 1, d.getDate() ].map(function(x) { return x < 10 ? '0' + x : String(x); }).join('-');
}

function summary(g) {
	if (!g || g.geoip == null)
		return '';
	return [ 'geoip ' + size(g.geoip), 'geosite ' + size(g.geosite), date(g.updated) ].filter(Boolean).join(' · ');
}

function result(g) {
	if (g.state === 'ok')
		return { msg: _('Geo databases updated & validated.'), kind: 'info' };
	if (g.state === 'unchanged')
		return { msg: _('Already up to date — nothing changed.'), kind: 'info' };
	return { msg: _('Geo update failed: ') + String(g.state || '').replace(/^error:\s*/, ''), kind: 'warning' };
}

return baseclass.extend({
	summary: summary,
	result: result
});
