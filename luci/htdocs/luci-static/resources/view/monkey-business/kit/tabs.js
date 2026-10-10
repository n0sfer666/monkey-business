'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';

style.add('tabs', [
	'#tabmenu{display:none!important}',
	'.mb.mb-tabs{display:flex;align-items:flex-end;gap:22px;margin-top:-6px;border-bottom:1px solid var(--mb-line);line-height:normal}',
	'.mb .mb-tabs-title{font-size:16px;font-weight:600;padding-bottom:9px;margin-right:10px}',
	'.mb .mb-tabs-nav{display:flex;gap:22px;font-size:14px}',
	'.mb a.mb-tab,.mb a.mb-tab:hover,.mb a.mb-tab:focus{padding:0 2px 9px;text-decoration:none;font-weight:500;',
	'color:var(--mb-muted);border-bottom:2px solid transparent}',
	'.mb a.mb-tab[aria-current="page"]{font-weight:600;color:var(--mb-text);border-bottom-color:var(--mb-accent)}',
	'.mb a.mb-tab:focus-visible{outline:2px solid var(--mb-accent);outline-offset:1px}',
	style.MOBILE + '{',
	'.mb.mb-tabs{flex-direction:column;align-items:stretch;gap:12px;margin-top:0;border-bottom:0}',
	'.mb .mb-tabs-title{font-size:18px;padding:0;margin:0}',
	'.mb .mb-tabs-nav{gap:4px;padding:4px;background:var(--mb-panel);border:1px solid var(--mb-line);border-radius:10px}',
	'.mb a.mb-tab,.mb a.mb-tab:hover,.mb a.mb-tab:focus{flex:1;display:flex;align-items:center;justify-content:center;',
	'height:36px;padding:0;border:0;border-radius:6px}',
	'.mb a.mb-tab[aria-current="page"]{background:var(--mb-btn-on);box-shadow:inset 0 -2px 0 var(--mb-accent)}',
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
			E('nav', { 'class': 'mb-tabs-nav', 'aria-label': _('Monkey Business') }, TABS.map(function(t) {
				return E('a', {
					'class': 'mb-tab',
					'href': L.url('admin/services/monkey-business', t[0]),
					'aria-current': t[0] === active ? 'page' : null
				}, [ t[1] ]);
			}))
		]);
	}
});
