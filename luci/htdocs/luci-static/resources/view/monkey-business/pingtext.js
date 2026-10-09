'use strict';
'require baseclass';

function text(ms, na, autoOff) {
	if (na)
		return _('n/a');
	if (ms != null)
		return ms + ' ms' + (autoOff ? ' · ' + _('auto-off') : '');
	return autoOff ? _('down · auto-off') : '—';
}

function results(res) {
	if (res && res.results)
		return res.results;
	return (res && res.id != null) ? [ res ] : [];
}

return baseclass.extend({
	text: text,
	results: results
});
