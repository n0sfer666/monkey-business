'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.model.servers as model';
'require view.monkey-business.srv.pingbar as pingbar';

style.add('servertiles', [
	'.mb .mb-tiles-hint{padding:10px 12px 0}',
	'.mb .mb-tiles{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px;padding:10px 12px 12px}',
	'.mb .mb-tile{display:flex;flex-direction:column;justify-content:space-between;min-width:0;height:72px;margin:0;padding:8px;',
	'background:var(--mb-btn);color:var(--mb-text);border:1px solid var(--mb-line);border-radius:8px;',
	'font:inherit;text-align:left;cursor:pointer;box-shadow:none}',
	'.mb .mb-tile[aria-pressed="true"]{background:var(--mb-accent-tint);border-color:var(--mb-accent)}',
	'.mb .mb-tile>span{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}',
	'.mb .mb-tile-n,.mb .mb-tile-ping{font-size:11px;color:var(--mb-muted)}',
	'.mb .mb-tile-name{font-size:13px;font-weight:500}',
	'.mb .mb-tile.mb-off .mb-tile-name{color:var(--mb-muted)}'
].join(''));

return baseclass.extend({
	render: function(o) {
		var picked = o.servers.filter(function(s) { return s['.name'] === o.picked; })[0];
		var hint = picked
			? _('Moving “%s” — tap the tile whose place it takes').format(model.title(picked))
			: _('Tap a server, then tap its new place. Gear again — done.');

		return [
			E('div', { 'class': 'mb-tiles-hint mb-muted mb-small', 'aria-live': 'polite' }, [ hint ]),
			E('div', { 'class': 'mb-tiles' }, o.servers.map(function(s, i) {
				var sid = s['.name'];
				return E('button', {
					'type': 'button',
					'data-sid': sid,
					'class': 'mb-tile' + (model.isOff(s) ? ' mb-off' : ''),
					'aria-pressed': sid === o.picked ? 'true' : 'false',
					'click': function() { o.onTap(sid); }
				}, [
					E('span', { 'class': 'mb-tile-n' }, [ '#' + (i + 1) ]),
					E('span', { 'class': 'mb-tile-name' }, [ model.title(s) ]),
					E('span', { 'class': 'mb-tile-ping' }, [ pingbar.label(o.ping(s)) ])
				]);
			}))
		];
	}
});
