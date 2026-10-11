'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.kit.seg as seg';

style.add('tabs', [
	'#tabmenu{display:none!important}',
	'.mb.mb-tabs{display:flex;align-items:center;gap:16px;margin-top:-6px;padding-bottom:10px;border-bottom:1px solid var(--mb-line);line-height:normal}',
	'.mb .mb-tabs-title{font-size:16px;font-weight:600}',
	style.MOBILE + '{',
	'.mb.mb-tabs{flex-direction:column;align-items:stretch;gap:12px;margin-top:0;padding-bottom:0;border-bottom:0}',
	'.mb .mb-tabs-title{font-size:18px}',
	'}'
].join(''));

var TABS = [
	[ 'dashboard', _('Dashboard') ],
	[ 'servers', _('Servers') ],
	[ 'settings', _('Settings') ]
];

return baseclass.extend({
	render: function(active) {
		return E('div', { 'class': 'mb mb-tabs' }, [
			E('span', { 'class': 'mb-tabs-title' }, [ _('Monkey Business') ]),
			seg.render({
				label: _('Monkey Business'),
				value: active,
				options: TABS.map(function(t) {
					return { value: t[0], label: t[1], href: L.url('admin/services/monkey-business', t[0]) };
				})
			})
		]);
	}
});
