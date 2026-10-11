'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.kit.seg as seg';
'require view.monkey-business.kit.tip as tip';
'require view.monkey-business.kit.icons as icons';
'require view.monkey-business.kit.busybtn as busybtn';

style.add('serverpanel', [
	'.mb .mb-srvs{--mb-srow-cols:20px 28px minmax(0,1fr) minmax(0,1.1fr) 130px 110px 150px 44px 64px;display:flex;flex-direction:column}',
	'.mb .mb-srvs-head{display:flex;flex-wrap:wrap;align-items:center;gap:8px 10px;padding:10px 12px;border-bottom:1px solid var(--mb-line)}',
	'.mb .mb-srvs-filter{margin-right:auto}',
	'.mb .mb-srvs-head .mb-btn{white-space:nowrap}',
	'.mb .mb-srvs-gear{display:none}',
	'.mb .mb-srvs-gear[aria-pressed="true"]{display:inline-flex;background:var(--mb-accent-tint);border-color:var(--mb-accent);color:var(--mb-accent-text)}',
	'.mb .mb-srvs-cols{display:grid;grid-template-columns:var(--mb-srow-cols);gap:10px;padding:7px 12px;',
	'border-bottom:1px solid var(--mb-line);color:var(--mb-muted);font-size:12px}',
	'.mb .mb-srvs-cols>*{min-width:0;white-space:nowrap}',
	'.mb .mb-srvs-empty{padding:10px 12px}',
	'@media (min-width:721px) and (max-width:1000px){',
	'.mb .mb-srvs{--mb-srow-cols:20px 24px minmax(0,1fr) 112px minmax(0,96px) 132px 36px 64px}',
	'.mb .mb-srvs-addr,.mb .mb-srow-addr{display:none}',
	'}',
	style.MOBILE + '{',
	'.mb .mb-srvs h2{flex:1;font-size:15px}',
	'.mb .mb-srvs-add{order:1}',
	'.mb .mb-srvs-gear{display:inline-flex;order:2}',
	'.mb .mb-srvs-filter{order:3;flex-basis:100%;margin:0}',
	'.mb .mb-srvs-ping,.mb .mb-srvs-sort{order:4;flex:1}',
	'.mb .mb-srvs-cols{display:none}',
	'}'
].join(''));

function gear(o) {
	var b = E('button', {
		'type': 'button', 'class': 'mb-btn mb-icon mb-srvs-gear', 'aria-pressed': o.moving ? 'true' : 'false',
		'aria-label': _('Reorder servers'), 'title': _('Reorder servers'), 'disabled': o.filter !== 'all' ? '' : null,
		'click': o.onGear
	});
	b.innerHTML = icons.GEAR;
	return b;
}

return baseclass.extend({
	render: function(o) {
		var sortBtn = E('button', {
			'type': 'button', 'class': 'mb-btn mb-btn-sm mb-srvs-sort', 'title': _('Reorder by latency, applied on Save & Apply'),
			'disabled': o.filter !== 'all' || !o.count || o.pinging ? '' : null, 'click': o.onSort
		}, busybtn.content(icons.SORT, _('Sort by ping')));
		return E('div', { 'class': 'mb-srvs-head' }, [
			E('h2', {}, [ _('Servers') ]),
			E('div', { 'class': 'mb-srvs-filter' }, o.filters.length > 1 ? [
				seg.render({ label: _('Show servers'), options: o.filters, value: o.filter, onChange: o.onFilter })
			] : []),
			busybtn.render({
				cls: 'mb-btn-sm mb-srvs-ping', icon: icons.PULSE, label: _('Ping all'), busy: _('Pinging %d servers…').format(o.count), pending: o.pinging,
				run: function() {
					sortBtn.disabled = true;
					return o.onPingAll();
				}
			})
		].concat(o.readonly ? [] : [
			sortBtn,
			E('button', { 'type': 'button', 'class': 'mb-btn mb-btn-sm mb-btn-tint mb-srvs-add', 'click': o.onAdd }, [ _('+ Add server') ]),
			gear(o)
		]));
	},

	cols: function() {
		return E('div', { 'class': 'mb-srvs-cols', 'aria-hidden': 'true' }, [
			'', '#', _('Name'), E('span', { 'class': 'mb-srvs-addr' }, [ _('Address') ]), _('Protocol'), _('Subscription'), _('Ping'),
			tip.render(_('Never used for connecting. Still listed and pinged.'), _('Off')), ''
		].map(function(c) { return typeof c === 'string' ? E('span', {}, [ c ]) : c; }));
	},

	relabel: function(root, filters) {
		seg.relabel(root, filters);
	}
});
