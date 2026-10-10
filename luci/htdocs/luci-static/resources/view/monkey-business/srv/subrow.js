'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.kit.inline as inline';
'require view.monkey-business.kit.icons as icons';
'require view.monkey-business.kit.busybtn as busybtn';
'require view.monkey-business.model.interval as interval';
'require view.monkey-business.model.subs as model';
'require view.monkey-business.srv.subinterval as subinterval';

style.add('subrow', [
	'.mb .mb-sub{display:grid;grid-template-columns:var(--mb-sub-cols);gap:12px;align-items:center;',
	'padding:6px 12px;min-height:40px;border-top:1px solid var(--mb-line-soft)}',
	'.mb .mb-sub-role{justify-self:start;border-radius:4px;padding:1px 8px;font-size:12px;background:var(--mb-line);color:var(--mb-text-2)}',
	'.mb .mb-sub-role.mb-on{background:var(--mb-ok-tint);color:var(--mb-ok-text)}',
	'.mb .mb-sub .mb-inl{justify-self:start}',
	'.mb .mb-sub-name{font-weight:500}',
	'.mb .mb-sub-auto{position:relative;justify-self:start}',
	'.mb .mb-sub-traf{display:flex;flex-direction:column;gap:3px;min-width:0}',
	'.mb .mb-sub-bar{height:4px;border-radius:2px;overflow:hidden;background:var(--mb-line)}',
	'.mb .mb-sub-bar>div{height:100%;background:var(--mb-accent)}',
	'.mb .mb-sub-bar>.mb-hot{background:var(--mb-warn)}',
	'.mb .mb-sub-acts{display:flex;gap:6px;justify-content:flex-end}',
	'.mb .mb-sub-acts .mb-btn:not(.mb-icon){padding:4px 10px;white-space:nowrap}',
	'.mb .mb-icon.mb-sub-del{color:var(--mb-err-text)}',
	'.mb .mb-sub-del,.mb .mb-sub-del:hover{border-color:var(--mb-err-edge)!important}',
	style.MOBILE + '{',
	'.mb .mb-sub{grid-template-columns:auto minmax(0,1fr) auto auto;row-gap:8px;padding:10px 12px;',
	'grid-template-areas:"role name name del" "url url url url" "bar bar bar bar" "text text fetch ping" "auto auto auto auto"}',
	'.mb .mb-sub-acts,.mb .mb-sub-traf{display:contents}',
	'.mb .mb-sub-role{grid-area:role}',
	'.mb .mb-sub .mb-sub-name{grid-area:name;width:100%;padding:6px 8px}',
	'.mb .mb-sub .mb-sub-url{grid-area:url;width:100%;padding:6px 8px}',
	'.mb .mb-sub-del{grid-area:del}',
	'.mb .mb-sub-fetch{grid-area:fetch}',
	'.mb .mb-sub-ping{grid-area:ping}',
	'.mb .mb-sub-acts .mb-btn:not(.mb-icon){padding:6px 10px}',
	'.mb .mb-sub-bar{grid-area:bar}',
	'.mb .mb-sub-ttext{grid-area:text}',
	'.mb .mb-sub-auto{grid-area:auto;justify-self:stretch}',
	'}'
].join(''));

function traffic(s) {
	var t = model.traffic(s);
	if (!t)
		return E('div', { 'class': 'mb-sub-traf' }, [ E('span', { 'class': 'mb-sub-ttext mb-muted mb-small' }, [ '—' ]) ]);
	return E('div', { 'class': 'mb-sub-traf' }, [
		E('div', { 'class': 'mb-sub-bar' }, [ E('div', { 'class': t.pct > 80 ? 'mb-hot' : '', 'style': 'width:' + t.pct + '%' }) ]),
		E('span', { 'class': 'mb-sub-ttext mb-muted mb-small' }, [
			t.used + ' / ' + t.total + ' GB' + (t.expire ? ' · ' + _('until %s').format(t.expire) : '')
		])
	]);
}

return baseclass.extend({
	render: function(o) {
		var s = o.sub;
		var sid = s['.name'];
		var minutes = interval.fromConfig(s.auto_update, s.update_interval);
		var setMinutes = function(n) { o.onInterval(sid, n); };

		var name = inline.render({
			value: s.name || '', placeholder: sid, label: _('Subscription name'), size: 24, readonly: o.readonly,
			validate: function(v) { return v ? null : _('Name must not be empty'); },
			onCommit: function(v) { o.onEdit(sid, 'name', v); }
		});
		var url = inline.render({
			value: s.url || '', placeholder: 'https://…', label: _('Subscription URL'), size: 40,
			mono: true, mask: model.maskUrl, validate: model.urlError, readonly: o.readonly,
			onCommit: function(v) { o.onEdit(sid, 'url', v); }
		});
		var del = E('button', {
			'type': 'button', 'class': 'mb-btn mb-icon mb-sub-del', 'aria-label': _('Delete subscription'),
			'title': _('Delete subscription'), 'aria-haspopup': 'dialog', 'click': function() { o.onDelete(sid); }
		});
		del.innerHTML = icons.TRASH;
		name.classList.add('mb-sub-name');
		url.classList.add('mb-sub-url');

		return E('div', { 'class': 'mb-sub', 'data-sub': sid }, [
			E('span', { 'class': 'mb-sub-role' + (o.active ? ' mb-on' : '') }, [ o.active ? _('active') : _('reserve') ]),
			name,
			url,
			E('div', { 'class': 'mb-sub-auto' }, subinterval.render('mb-sub-auto-' + sid, minutes, setMinutes, o.readonly)),
			traffic(s),
			E('div', { 'class': 'mb-sub-acts' }, [
				o.readonly ? '' : busybtn.render({ cls: 'mb-sub-fetch', label: _('Fetch'), busy: _('Fetching…'), run: function() { return o.onFetch(sid); } }),
				busybtn.render({ cls: 'mb-sub-ping', label: _('Ping'), busy: _('Pinging…'), run: function() { return o.onPing(sid); } }),
				o.readonly ? '' : del
			])
		]);
	}
});
