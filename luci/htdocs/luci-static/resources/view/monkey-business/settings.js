'use strict';
'require view';
'require dom';
'require ui';
'require view.monkey-business.api as api';
'require view.monkey-business.store as store';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.set.sections as sections';

style.add('set-view', [
	'.mb.mb-set{display:flex;flex-direction:column;gap:14px;padding:4px 0 16px}',
	'.mb .mb-set-bar{display:flex;align-items:center;gap:12px}',
	'.mb .mb-set-hint{flex:1;min-width:0}',
	'.mb .mb-set-acts{display:flex;gap:8px}',
	style.MOBILE + '{',
	'.mb.mb-set{padding-bottom:0}',
	'.mb .mb-set-bar{display:contents}',
	'.mb .mb-set-acts{order:2;position:sticky;bottom:0;z-index:2;padding:10px 12px;',
	'background:var(--mb-bar);border-top:1px solid var(--mb-line)}',
	'.mb .mb-set-acts .mb-btn-primary{flex:1}',
	'}'
].join(''));

function notify(text, level) {
	ui.addNotification(null, E('p', {}, [ text ]), level);
}

function report(res) {
	if (res && res.error)
		return notify(_('Apply failed: ') + res.error, 'warning');
	if (res && res.skipped == 'disabled')
		return notify(_('Saved. The VPN is off — settings will apply when you turn it on.'), 'info');
	notify(_('Configuration applied.'), 'info');
}

return view.extend({
	handleSave: null,
	handleSaveApply: null,
	handleReset: null,

	load: function() {
		return store.load();
	},

	render: function() {
		this.root = E('div', { 'class': 'mb mb-set' });
		this.draw();
		return this.root;
	},

	draw: function() {
		var self = this;
		var errors = {};
		var locked = !L.hasViewPermission();

		function act(name) {
			return ui.createHandlerFn(self, function() {
				locked = true;
				sync();
				return self[name]();
			});
		}

		var reset = E('button', { 'class': 'mb-btn', 'click': act('doReset') }, [ _('Reset') ]);
		var save = E('button', { 'class': 'mb-btn', 'click': act('doSave') }, [ _('Save') ]);
		var apply = E('button', { 'class': 'mb-btn mb-btn-primary', 'click': act('doApply') }, [ _('Save & Apply') ]);

		function sync() {
			var bad = locked || Object.keys(errors).length > 0;
			var dirty = store.dirty();
			reset.disabled = locked || !dirty;
			save.disabled = bad || !dirty;
			apply.disabled = bad;
		}

		dom.content(this.root, [
			E('div', { 'class': 'mb-set-bar' }, [
				E('div', { 'class': 'mb-set-hint mb-muted mb-small' }, [ _('Each option has a hint. Defaults are safe.') ]),
				E('div', { 'class': 'mb-set-acts' }, [ reset, save, apply ])
			]),
			sections.render(errors, sync)
		]);
		sync();
	},

	doReset: function() {
		return store.reset().then(this.draw.bind(this)).catch(function() {
			window.location.reload();
		});
	},

	doSave: function() {
		return store.save().catch(function(e) {
			notify(_('Save failed: ') + e, 'error');
		}).then(this.draw.bind(this));
	},

	doApply: function() {
		return store.apply().then(function() {
			return api.configApply();
		}).then(report).catch(function(e) {
			notify(_('Apply failed: ') + e, 'error');
		}).then(this.draw.bind(this));
	}
});
