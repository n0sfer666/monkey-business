'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.kit.icons as icons';
'require view.monkey-business.kit.menu as menu';
'require view.monkey-business.model.servers as model';
'require view.monkey-business.srv.pingbar as pingbar';

style.add('serverrow', [
	'.mb .mb-srow{display:grid;grid-template-columns:var(--mb-srow-cols);gap:10px;align-items:center;',
	'padding:3px 12px;min-height:43px;border-bottom:1px solid var(--mb-line-soft)}',
	'.mb .mb-srow.mb-dim{color:var(--mb-dim)}',
	'.mb .mb-srow>*{min-width:0}',
	'.mb .mb-srow-grip{display:flex;align-items:center;justify-content:flex-start;width:20px;height:28px;padding:0;margin:0;',
	'background:none;border:0;border-radius:4px;color:inherit;fill:var(--mb-faint);cursor:grab;box-shadow:none}',
	'.mb .mb-srow-grip svg{fill:inherit}',
	'.mb .mb-srow-grip:hover,.mb .mb-srow-grip:focus-visible{fill:var(--mb-text);box-shadow:none}',
	'.mb .mb-srow-grip:focus-visible{outline:2px solid var(--mb-accent)}',
	'.mb .mb-srow-grip[aria-disabled="true"]{visibility:hidden}',
	'.mb .mb-srow-n{color:var(--mb-muted);font-family:var(--mb-mono)}',
	'.mb .mb-srow-name,.mb .mb-srow-line{display:flex;align-items:center;gap:8px;max-width:100%}',
	'.mb .mb-srow-line>*{min-width:0}',
	'.mb .mb-srow-title,.mb .mb-srow-cut{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}',
	'.mb .mb-srow-badge{flex-shrink:0;padding:0 6px;border-radius:4px;font-size:11px;background:var(--mb-warn-tint);color:var(--mb-warn-text)}',
	'.mb .mb-srow-addr{color:var(--mb-text-2)}',
	'.mb .mb-srow-proto,.mb .mb-srow-src{color:var(--mb-muted)}',
	'.mb .mb-srow-meta,.mb .mb-srow-more{display:none}',
	'.mb .mb-srow-acts{display:flex;gap:4px;justify-content:flex-end}',
	'.mb .mb-srow-acts .mb-icon{border-radius:5px}',
	'.mb .mb-srow-gap{flex-shrink:0;width:28px}',
	'.mb .mb-icon.mb-srow-del{color:var(--mb-err-icon)}',
	'.mb .mb-srow-acts svg,.mb .mb-srow-more svg{display:block;margin:auto}',
	style.MOBILE + '{',
	'.mb .mb-srow{grid-template-columns:16px minmax(0,1fr) auto 36px;gap:10px;padding:8px 12px;min-height:56px}',
	'.mb .mb-srow-grip,.mb .mb-srow-addr,.mb .mb-srow-proto,.mb .mb-srow-src,.mb .mb-srow-off,.mb .mb-srow-acts{display:none}',
	'.mb .mb-srow:last-child{border-bottom:0}',
	'.mb .mb-srow-name{flex-direction:column;align-items:flex-start;gap:2px}',
	'.mb .mb-srow-meta{display:block;max-width:100%}',
	'.mb .mb-srow-more{display:inline-flex}',
	'}'
].join(''));

function iconBtn(cls, icon, label, run) {
	var b = E('button', { 'type': 'button', 'class': 'mb-btn mb-icon ' + cls, 'aria-label': label, 'title': label, 'click': run });
	b.innerHTML = icon;
	return b;
}

function grip(o, sid, name) {
	var b = E('span', {
		'role': 'button', 'class': 'mb-srow-grip', 'draggable': o.movable ? 'true' : 'false',
		'tabindex': o.movable ? '0' : '-1', 'aria-disabled': o.movable ? 'false' : 'true',
		'aria-label': _('Move %s: drag, or press ↑ ↓').format(name), 'title': _('Drag to reorder, or press ↑ ↓')
	});
	b.innerHTML = icons.GRIP;
	b.addEventListener('keydown', function(ev) {
		if (!o.movable || (ev.key !== 'ArrowUp' && ev.key !== 'ArrowDown'))
			return;
		ev.preventDefault();
		o.onStep(sid, ev.key === 'ArrowUp' ? -1 : 1);
	});
	return b;
}

function actions(o, sid, off, manual) {
	var items = o.pingable ? [ { label: _('Ping'), run: function() { o.onPing(sid); } } ] : [];
	if (o.readonly)
		return items;
	if (manual)
		items.push({ label: _('Edit'), run: function() { o.onEdit(sid); } });
	items.push({ label: off ? _('Turn on') : _('Turn off'), kind: off ? null : 'warn', run: function() { o.onOff(sid, !off); } });
	items.push('-', { label: _('Delete'), kind: 'danger', run: function() { o.onDelete(sid); } });
	return items;
}

function buttons(o, sid, name, manual) {
	if (o.readonly)
		return [];
	return [
		manual ? iconBtn('mb-srow-edit', icons.PEN, _('Edit %s').format(name), function() { o.onEdit(sid); }) : E('span', { 'class': 'mb-srow-gap' }),
		iconBtn('mb-srow-del', icons.BIN, _('Delete %s').format(name), function() { o.onDelete(sid); })
	];
}

function source(subName) {
	return subName || _('manual');
}

function meta(s, src) {
	return model.protocol(s) + ' · ' + src;
}

return baseclass.extend({
	render: function(o) {
		var s = o.server;
		var sid = s['.name'];
		var off = model.isOff(s);
		var manual = model.isManual(s);
		var name = model.title(s);
		var src = source(o.subName);

		var check = E('input', { 'type': 'checkbox', 'class': 'mb-xbox mb-srow-check', 'title': _('Never used for connecting. Still listed and pinged.'), 'aria-label': _('Off: %s').format(name) });
		check.checked = off;
		check.disabled = !!o.readonly;
		check.addEventListener('change', function() { o.onOff(sid, check.checked); });

		var items = actions(o, sid, off, manual);
		var more = iconBtn('mb-srow-more', icons.MORE, _('Actions for %s').format(name), function() {
			menu.open(more, items);
		});
		more.style.visibility = items.length ? '' : 'hidden';
		more.setAttribute('aria-haspopup', 'menu');
		more.setAttribute('aria-expanded', 'false');

		return E('div', { 'class': 'mb-srow' + (off || o.ping.kind === 'off' ? ' mb-dim' : ''), 'data-sid': sid, 'role': 'listitem' }, [
			grip(o, sid, name),
			E('span', { 'class': 'mb-srow-n' }, [ String(o.n) ]),
			E('div', { 'class': 'mb-srow-name' }, [
				E('div', { 'class': 'mb-srow-line' }, [
					E('span', { 'class': 'mb-srow-title', 'title': name }, [ name ]),
					off ? E('span', { 'class': 'mb-srow-badge' }, [ _('off') ]) : ''
				]),
				E('span', { 'class': 'mb-srow-meta mb-srow-cut mb-muted mb-small' }, [ meta(s, src) ])
			]),
			E('span', { 'class': 'mb-srow-addr mb-srow-cut mb-mono', 'title': model.endpoint(s) }, [ model.endpoint(s) ]),
			E('span', { 'class': 'mb-srow-proto mb-srow-cut' }, [ model.protocol(s) ]),
			E('span', { 'class': 'mb-srow-src mb-srow-cut', 'title': src }, [ src ]),
			pingbar.render(o.ping),
			E('label', { 'class': 'mb-srow-off' }, [ check ]),
			E('div', { 'class': 'mb-srow-acts' }, buttons(o, sid, name, manual)),
			more
		]);
	},

	relabel: function(row, s, nameOf) {
		if (!s)
			return;
		var src = source(nameOf(s));
		var cell = row.querySelector('.mb-srow-src');
		row.querySelector('.mb-srow-meta').textContent = meta(s, src);
		cell.textContent = src;
		cell.title = src;
	}
});
