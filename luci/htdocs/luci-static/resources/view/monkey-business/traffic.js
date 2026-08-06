'use strict';
'require baseclass';

// Остаток трафика подписки. Рисуется, только если подписка его вообще прислала:
// пустая полоса «0 / 0 GB» выглядела бы как исчерпанный лимит.
function toGB(bytes) {
	var n = parseFloat(bytes);
	if (isNaN(n) || n <= 0) return 0;
	return n / 1073741824;
}

function fmtDate(epoch) {
	var n = parseInt(epoch, 10);
	if (isNaN(n) || n <= 0) return '-';
	return new Date(n * 1000).toISOString().slice(0, 10);
}

return baseclass.extend({
	render: function(t) {
		if (!t || !t.total || toGB(t.total) <= 0)
			return E([]);
		var used = toGB(t.used_download) + toGB(t.used_upload);
		var total = toGB(t.total);
		var pct = total > 0 ? Math.min(100, Math.round(used / total * 100)) : 0;
		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ _('Subscription traffic') ]),
			E('p', {}, [ used.toFixed(1) + ' / ' + total.toFixed(1) + ' GB (' + pct + '%)' ]),
			E('div', { 'style': 'background:#ddd;border-radius:4px;height:14px;width:100%;max-width:420px;overflow:hidden' }, [
				E('div', { 'style': 'background:' + (pct < 90 ? '#33a02c' : '#e31a1c') + ';height:14px;width:' + pct + '%' }, [])
			]),
			E('p', { 'style': 'color:#888' }, [ _('Expires: ') + fmtDate(t.expire) ])
		]);
	}
});
