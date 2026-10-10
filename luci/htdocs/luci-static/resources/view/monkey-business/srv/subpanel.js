'use strict';
'require baseclass';
'require dom';
'require view.monkey-business.api as api';
'require view.monkey-business.store as store';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.kit.confirm as confirm';
'require view.monkey-business.kit.notify as notice';
'require view.monkey-business.kit.refocus as refocus';
'require view.monkey-business.kit.progress as progress';
'require view.monkey-business.model.subs as model';
'require view.monkey-business.model.interval as interval';
'require view.monkey-business.model.confirmtext as confirmtext';
'require view.monkey-business.srv.subrow as subrow';
'require view.monkey-business.srv.subsheet as subsheet';
'require view.monkey-business.srv.subreport as report';
'require view.monkey-business.srv.subpersist as subpersist';

style.add('subpanel', [
	'.mb .mb-subs{--mb-sub-cols:72px minmax(96px,1fr) minmax(120px,1.3fr) minmax(96px,140px) minmax(0,180px) auto;display:flex;flex-direction:column}',
	'.mb .mb-subs-head{display:flex;align-items:center;gap:12px;padding:10px 12px}',
	'.mb .mb-subs-head .mb-muted{flex:1;min-width:0}',
	'.mb .mb-subs-cols{display:grid;grid-template-columns:var(--mb-sub-cols);gap:12px;padding:7px 12px;',
	'border-top:1px solid var(--mb-line);color:var(--mb-muted);font-size:12px}',
	'.mb .mb-subs-empty{padding:12px;border-top:1px solid var(--mb-line-soft)}',
	'.mb .mb-subs-short{display:none}',
	style.MOBILE + '{',
	'.mb .mb-subs{border-radius:10px}',
	'.mb .mb-subs-head .mb-muted{display:none}',
	'.mb .mb-subs-head h2{flex:1;font-size:15px}',
	'.mb .mb-subs-cols,.mb .mb-subs-long{display:none}',
	'.mb .mb-subs-short{display:inline}',
	'}'
].join(''));

var WAIT = _('Downloading the server list, this can take up to a minute.');

function nameOf(sid) {
	return model.title({ '.name': sid, 'name': store.get(sid, 'name') });
}

return baseclass.extend({
	create: function(o) {
		var root = E('section', { 'class': 'mb-panel mb-subs' });

		var persist = subpersist.create(o);

		function addBtn() {
			return root.querySelector('.mb-subs-add');
		}

		function edited(sid, opt, v) {
			store.set(sid, opt, v);
			if (opt === 'name')
				return o.onRename();
			o.onChange();
		}

		function setMinutes(sid, n) {
			var c = interval.toConfig(n);
			store.set(sid, 'auto_update', c.auto_update);
			if (c.update_interval)
				store.set(sid, 'update_interval', c.update_interval);
			o.onChange();
		}

		function fetchSub(sid) {
			var url = store.get(sid, 'url') || '';
			var name = nameOf(sid);
			if (model.urlError(url)) {
				notice.show(_('Enter a subscription URL first.'), 'warning');
				return Promise.resolve();
			}
			return o.hold(function() {
				return persist(function() {
					return progress.run(_('Fetching “%s”…').format(name), WAIT, function() {
						return api.subscriptionUpdate(sid, url);
					}).then(function(res) {
						report.fetch(name, res);
					});
				}).catch(notice.fail(_('Fetch error: ')));
			}, function() {
				return root.querySelector('[data-sub="' + CSS.escape(sid) + '"] .mb-sub-fetch');
			});
		}

		function ping(sid) {
			return api.subscriptionPing(sid).then(function(res) {
				report.ping(res);
				if (!(res && res.error))
					o.onPing(res);
			}).catch(notice.fail(_('Ping failed: ')));
		}

		function remove(sid) {
			var list = store.sections('subscription');
			var gone = model.serversOf(store.sections('server'), sid);
			var rest = list.filter(function(s) { return s['.name'] !== sid; });
			var next = model.activeId(list, store.get('global', 'active_sub')) === sid && rest.length ? rest[0]['.name'] : null;
			var text = confirmtext.deleteSub({ name: nameOf(sid), count: gone.length, next: next && nameOf(next) });
			return confirm.ask({
				title: text.title,
				body: text.body,
				actions: [
					{ label: _('Cancel'), kind: 'cancel', value: false },
					{ label: _('Delete'), kind: 'danger', value: true }
				]
			}).then(function(ok) {
				if (!ok)
					return;
				gone.forEach(function(s) { store.remove(s['.name']); });
				store.remove(sid);
				if (next)
					store.set('global', 'active_sub', next);
				refocus.around(root, { pattern: /^mb-sub-del$/, attr: 'data-sub', spare: addBtn }, draw);
				o.onRemove();
			});
		}

		function add() {
			var list = store.sections('subscription');
			var active = model.activeId(list, store.get('global', 'active_sub'));
			var first = model.vacant(active && store.get(active), store.sections('server'));
			subsheet.open({
				name: model.defaultName(list.length),
				hint: first ? _('Becomes the active subscription') : _('A reserve until you switch to it on the Dashboard'),
				back: addBtn,
				onAdd: function(name, url) {
					return o.hold(function() {
						return persist(function() {
							return api.subscriptionAdd(name, url).then(function(res) {
								if (!(res && res.error))
									report.fetch(name, res);
								return res;
							});
						});
					}, null);
				}
			});
		}

		function draw() {
			var list = store.sections('subscription');
			var active = model.activeId(list, store.get('global', 'active_sub'));
			var rows = list.map(function(s) {
				return subrow.render({
					sub: s,
					active: s['.name'] === active,
					readonly: o.readonly,
					onEdit: edited,
					onInterval: setMinutes,
					onFetch: fetchSub,
					onPing: ping,
					onDelete: remove
				});
			});
			dom.content(root, [
				E('div', { 'class': 'mb-subs-head' }, [
					E('h2', {}, [ _('Subscriptions') ]),
					E('span', { 'class': 'mb-muted' }, [ _('the active one is used first, the rest are a reserve') ]),
					o.readonly ? '' : E('button', { 'type': 'button', 'class': 'mb-btn mb-btn-tint mb-subs-add', 'click': add }, [
						E('span', { 'class': 'mb-subs-long' }, [ _('+ Add subscription') ]),
						E('span', { 'class': 'mb-subs-short' }, [ _('+ Add') ])
					])
				]),
				rows.length ? E('div', { 'class': 'mb-subs-cols' }, [ _('Role'), _('Name'), _('URL'), _('Auto-update'), _('Traffic'), '' ].map(function(t) {
					return E('span', {}, [ t ]);
				})) : E('div', { 'class': 'mb-subs-empty mb-muted' }, [ _('No subscriptions yet. Add the VPNON link to get servers.') ])
			].concat(rows));
		}

		function refetch(ids) {
			if (!ids.length)
				return Promise.resolve();
			return progress.run(_('Fetching subscriptions…'), WAIT, function() {
				return ids.reduce(function(chain, sid) {
					return chain.then(function() {
						return api.subscriptionUpdate(sid, '').then(function(res) {
							report.fetch(nameOf(sid), res);
						}, notice.fail(_('Fetch error: ')));
					});
				}, Promise.resolve());
			});
		}

		draw();
		return { node: root, draw: draw, refetch: refetch };
	}
});
