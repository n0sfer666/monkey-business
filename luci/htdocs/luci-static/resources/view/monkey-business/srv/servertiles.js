'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.model.servers as model';
'require view.monkey-business.srv.pingbar as pingbar';

style.add('servertiles', [
	'.mb .mb-tiles-hint{padding:0 12px 8px;font-size:12px;line-height:15px}',
	'.mb .mb-tiles-hint.mb-picked{color:var(--mb-accent-text)}',
	'.mb .mb-tiles{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px;padding:4px 12px 12px}',
	'.mb .mb-tile{display:flex;flex-direction:column;align-items:flex-start;gap:4px;min-width:0;height:72px;margin:0;padding:8px 10px;',
	'background:var(--mb-btn);color:var(--mb-text);border:1px solid var(--mb-line-strong);border-radius:8px;',
	'font:inherit;text-align:left;cursor:pointer;box-shadow:none}',
	'.mb .mb-tiles.mb-picking .mb-tile{border-style:dashed;border-color:var(--mb-dash)}',
	'.mb .mb-tiles .mb-tile[aria-pressed="true"]{background:var(--mb-pick);border:2px solid var(--mb-accent)!important;box-shadow:0 0 0 3px var(--mb-pick-ring)}',
	'.mb .mb-tile.mb-dim{color:var(--mb-dim)}',
	'.mb .mb-tile>span{width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}',
	'.mb .mb-tile-top{display:flex;align-items:center;justify-content:space-between;font-size:11px;color:var(--mb-muted)}',
	'.mb .mb-tile-badge{padding:0 5px;border-radius:4px;background:var(--mb-warn-tint);color:var(--mb-warn-text)}',
	'.mb .mb-tile-name{font-size:13px}',
	'.mb .mb-tile-ping{font-family:var(--mb-mono);font-size:12px;color:var(--mb-muted)}',
	'.mb .mb-tile-fast{color:var(--mb-ok-text)}',
	'.mb .mb-tile-slow{color:var(--mb-slow)}',
	'.mb .mb-tile-off{color:var(--mb-err-text)}'
].join(''));

function tile(o, s, n) {
	var sid = s['.name'];
	var p = o.ping(s);
	var off = model.isOff(s);
	var name = model.title(s);
	var known = p.kind === 'na' || p.kind === 'off' || p.ms != null;
	return E('button', {
		'type': 'button',
		'data-sid': sid,
		'class': 'mb-tile' + (off || p.kind === 'off' ? ' mb-dim' : ''),
		'aria-pressed': sid === o.picked ? 'true' : 'false',
		'aria-label': [ n + '. ' + name ].concat(off ? [ _('off') ] : [], known ? [ pingbar.label(p) ] : []).join(', '),
		'click': function() { o.onTap(sid); }
	}, [
		E('span', { 'class': 'mb-tile-top' }, [
			E('span', {}, [ String(n) ]),
			off ? E('span', { 'class': 'mb-tile-badge' }, [ _('off') ]) : ''
		]),
		E('span', { 'class': 'mb-tile-name' }, [ name ]),
		E('span', { 'class': 'mb-tile-ping mb-tile-' + p.kind }, [ pingbar.label(p) ])
	]);
}

function moving(servers, sid) {
	var picked = servers.filter(function(s) { return s['.name'] === sid; })[0];
	return picked ? _('Moving "%s" — tap the tile whose place it takes').format(model.title(picked)) : '';
}

return baseclass.extend({
	moving: moving,

	render: function(o) {
		var picked = moving(o.servers, o.picked);
		var hint = picked || _('Tap a server, then tap its new place. Gear again — done.');

		return [
			E('div', { 'class': 'mb-tiles-hint mb-muted' + (picked ? ' mb-picked' : '') }, [ hint ]),
			E('div', { 'class': 'mb-tiles' + (picked ? ' mb-picking' : '') }, o.servers.map(function(s, i) {
				return tile(o, s, i + 1);
			}))
		];
	}
});
