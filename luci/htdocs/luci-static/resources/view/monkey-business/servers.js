'use strict';
'require view';
'require view.monkey-business.api as api';
'require view.monkey-business.store as store';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.kit.tabs as tabs';
'require view.monkey-business.kit.notify as notice';
'require view.monkey-business.kit.gesture as gesture';
'require view.monkey-business.model.subs as submodel';
'require view.monkey-business.srv.subpanel as subpanel';
'require view.monkey-business.srv.serverpanel as serverpanel';

style.add('servers-view', [
	'.mb.mb-srv-view{display:flex;flex-direction:column;gap:14px;padding:4px 0 16px}',
	'.mb .mb-srv-bar{display:flex;align-items:center;gap:12px}',
	'.mb .mb-srv-title{display:flex;align-items:center;gap:12px;flex:1;min-width:0}',
	'.mb .mb-srv-hint{flex:1;min-width:0}',
	'.mb .mb-srv-acts{display:flex;gap:12px}',
	style.MOBILE + '{',
	'.mb.mb-srv-view{gap:12px;padding:0 11px}',
	'.mb .mb-srv-bar{display:contents}',
	'.mb .mb-srv-title{flex-direction:column;align-items:flex-start;gap:2px}',
	'.mb .mb-srv-bar h1{font-size:18px}',
	'.mb .mb-srv-hint{font-size:13px}',
	'.mb .mb-srv-acts{order:2;position:sticky;bottom:0;z-index:2;gap:8px;margin:0 -16px;padding:12px 16px;',
	'background:var(--mb-bar);border-top:1px solid var(--mb-line)}',
	'.mb .mb-srv-acts .mb-btn-primary{flex:1}',
	'}'
].join(''));

function report(res) {
	if (res && res.error)
		return notice.show(_('Apply failed: ') + res.error, 'warning');
	if (res && res.skipped == 'disabled')
		return notice.show(_('Saved. The VPN is off — the new order will apply when you turn it on.'), 'info');
	notice.show(_('Applied — connected to: ') + ((res && res.server) || '?'), 'info');
}

return view.extend({
	handleSave: null,
	handleSaveApply: null,
	handleReset: null,

	load: function() {
		return Promise.all([ store.load(), api.serversList().catch(function() { return null; }) ]);
	},

	render: function(data) {
		var self = this;
		var readonly = !L.hasViewPermission();
		var busy = false;

		function usable(el) {
			return !!(el && el.isConnected && !el.disabled);
		}

		function hold(work, back, spare) {
			busy = true;
			self.sync();
			return Promise.resolve().then(work).finally(function() {
				busy = false;
				self.sync();
				var to = usable(back) ? back : spare && spare();
				if (usable(to))
					to.focus();
			});
		}

		function act(name) {
			return function(ev) {
				var back = ev.currentTarget;
				if (busy)
					return;
				back.classList.add('spinning');
				return hold(function() { return self[name](); }, back, function() { return self.apply; }).finally(function() {
					back.classList.remove('spinning');
				});
			};
		}

		this.reset = E('button', { 'class': 'mb-btn', 'click': act('doReset') }, [ _('Reset') ]);
		this.save = E('button', { 'class': 'mb-btn', 'click': act('doSave') }, [ _('Save') ]);
		this.apply = E('button', { 'class': 'mb-btn mb-btn-primary', 'click': act('doApply') }, [ _('Save & Apply') ]);
		this.sync = function() {
			var locked = readonly || busy;
			var dirty = store.dirty();
			self.root.inert = busy;
			self.reset.disabled = locked || !dirty;
			self.save.disabled = locked || !dirty;
			self.apply.disabled = locked;
		};

		this.servers = serverpanel.create({ list: data[1], readonly: readonly, onChange: this.sync });
		this.subs = subpanel.create({
			onChange: this.sync,
			onRename: function() { gesture.after(self.servers.relabel); self.sync(); },
			onRemove: function() { self.servers.draw(); self.sync(); },
			onFail: function() { self.draw(); },
			onReload: this.renew.bind(this),
			onSaved: this.servers.saved,
			readonly: readonly,
			hold: function(work, spare) { return hold(work, null, spare); },
			onPing: this.servers.onPing
		});
		this.root = E('div', { 'class': 'mb mb-srv-view' }, [
			tabs.render('servers'),
			E('div', { 'class': 'mb-srv-bar' }, [
				E('div', { 'class': 'mb-srv-title' }, [
					E('h1', {}, [ _('Servers') ]),
					E('span', { 'class': 'mb-srv-hint mb-muted' }, [ _('Row order is the connect priority') ])
				]),
				E('div', { 'class': 'mb-srv-acts' }, [ this.reset, this.save, this.apply ])
			]),
			this.subs.node,
			this.servers.node
		]);
		this.sync();
		return this.root;
	},

	draw: function() {
		this.subs.draw();
		this.servers.draw();
		this.sync();
	},

	reload: function() {
		var self = this;
		return store.reset().then(function() {
			self.servers.reset();
			self.draw();
		});
	},

	renew: function() {
		var self = this;
		this.servers.forget();
		return this.reload().then(function() {
			return self.servers.relist();
		});
	},

	doReset: function() {
		return this.reload().catch(function() {
			window.location.reload();
		});
	},

	doSave: function() {
		return store.save(this.servers.saved).catch(notice.fail(_('Save failed: '))).then(this.draw.bind(this));
	},

	doApply: function() {
		var self = this;
		var ids = [];
		return store.save(this.servers.saved).then(function() {
			return store.changes();
		}).then(function(changes) {
			ids = submodel.refetch(changes, store.sections('subscription').map(function(s) { return s['.name']; }));
			return store.commit();
		}).then(function() {
			return self.subs.refetch(ids);
		}).then(function() {
			return self.renew();
		}).then(function() {
			return api.status();
		}).then(function(st) {
			if (st && st.running)
				return api.configApply().then(report);
			notice.show(_('Saved. Turn on to connect to the top-priority server.'), 'info');
		}).catch(function(e) {
			notice.fail(_('Save & Apply failed: '))(e);
			self.draw();
		});
	}
});
