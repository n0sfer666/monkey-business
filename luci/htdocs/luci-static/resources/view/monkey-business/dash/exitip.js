'use strict';
'require baseclass';
'require view.monkey-business.api as api';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.kit.guard as guard';

style.add('dash-exit', [
	'.mb .mb-dash-exitrow{display:flex;align-items:center;gap:8px;min-width:0}',
	'.mb .mb-dash-exitip{min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}',
	style.MOBILE + '{',
	'.mb .mb-dash-field.mb-dash-exit{flex-direction:row;align-items:center;gap:8px}',
	'.mb .mb-dash-exit .mb-dash-exitrow{flex-grow:1}',
	'.mb .mb-dash-exitip{flex-grow:1}',
	'.mb .mb-dash-exit .mb-link{padding:6px 0}',
	'}'
].join(''));

function text(r) {
	if (r && r.error)
		return r.error;
	return (r.ip || '?') + (r.code ? ' · ' + r.code : '');
}

return baseclass.extend({
	render: function() {
		var value = E('span', { 'class': 'mb-mono mb-dash-exitip', 'aria-live': 'polite' }, [ '—' ]);
		var check = E('button', { 'type': 'button', 'class': 'mb-link', 'title': _('Probes ip-api.com through the split rules') }, [ _('Check') ]);

		check.addEventListener('click', function() {
			guard.run(check, function() {
				value.textContent = _('checking…');
				return api.checkExit('').then(function(r) {
					value.textContent = text(r || {});
					value.title = (r && r.country) || '';
				}).catch(function(e) {
					value.textContent = '' + e;
				});
			});
		});

		return E('div', { 'class': 'mb-dash-field mb-dash-exit' }, [
			E('span', { 'class': 'mb-muted mb-small' }, [ _('Exit IP') ]),
			E('div', { 'class': 'mb-dash-exitrow' }, [ value, check ])
		]);
	}
});
