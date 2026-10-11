'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.kit.icons as icons';

style.add('dash-geoneed', [
	'.mb .mb-dash-geoneed{display:flex;align-items:center;gap:8px;padding:8px 10px;background:var(--mb-err-soft);',
	'border:1px solid var(--mb-err-soft-edge);border-radius:6px;color:var(--mb-err-text)}',
	'.mb .mb-dash-geoneed>svg{flex-shrink:0}',
	'.mb .mb-dash-geotext{display:flex;align-items:center;gap:8px;flex-grow:1;min-width:0}',
	'.mb .mb-dash-geotext>span{flex-grow:1}',
	style.MOBILE + '{',
	'.mb .mb-dash-geoneed{align-items:flex-start;padding:10px;border-radius:8px;font-size:13px}',
	'.mb .mb-dash-geoneed>svg{width:16px;height:16px}',
	'.mb .mb-dash-geotext{flex-direction:column;align-items:flex-start;gap:6px}',
	'}'
].join(''));

function missingText(geo) {
	var files = [];
	if (!(geo.geoip > 0))
		files.push('geoip.dat');
	if (!(geo.geosite > 0))
		files.push('geosite.dat');
	return files.join(', ');
}

function missing(geo) {
	return !!geo && geo.geoip != null && geo.geosite != null && missingText(geo) !== '';
}

return baseclass.extend({
	missing: missing,
	missingText: missingText,

	render: function(onUpdate, readonly) {
		var wide = E('span', { 'class': 'mb-dash-wide' });
		var narrow = E('span', { 'class': 'mb-dash-narrow' });
		var box = E('div', { 'id': 'mb-dash-geoneed', 'class': 'mb-dash-geoneed', 'role': 'alert', 'hidden': '' }, [
			E('span', { 'class': 'mb-dash-geotext' }, [
				E('span', {}, [ wide, narrow ]),
				E('button', { 'type': 'button', 'class': 'mb-link', 'aria-haspopup': 'dialog', 'disabled': readonly ? '' : null, 'click': onUpdate }, [ _('Update geo data…') ])
			])
		]);
		box.insertAdjacentHTML('afterbegin', icons.WARN);

		return {
			node: box,
			update: function(geo) {
				var files = missing(geo) ? missingText(geo) : '';
				box.hidden = files === '';
				wide.textContent = _("Can't turn on: geo data is missing (%s). Xray needs both geoip.dat and geosite.dat.").format(files);
				narrow.textContent = _("Can't turn on: geo data is missing (%s).").format(files);
			}
		};
	}
});
