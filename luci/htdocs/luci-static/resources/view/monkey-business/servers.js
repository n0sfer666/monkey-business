'use strict';
'require view';
'require form';
'require rpc';
'require ui';

var callSubUpdate = rpc.declare({
	object: 'monkey-business', method: 'subscription_update', params: ['url']
});

function notifyResult(res) {
	if (res && res.error)
		ui.addNotification(null, E('p', _('Subscription update failed: ') + res.error), 'warning');
	else
		ui.addNotification(null, E('p', _('Servers fetched: ') + ((res && res.added) || 0)), 'info');
	return res;
}

return view.extend({
	render: function() {
		var m = new form.Map('monkey-business', _('Servers'),
			_('Subscription (VPNON) and manual servers.'));

		var sub = m.section(form.NamedSection, 'subscription', 'subscription',
			_('Subscription'));

		var url = sub.option(form.Value, 'url', _('Subscription URL'),
			_('VPNON subscription link. Type it and press "Fetch subscription" — it is saved automatically when the fetch succeeds.'));
		url.password = true;

		var auto = sub.option(form.Flag, 'auto_update', _('Auto-update'),
			_('Refresh the server list on a schedule.'));
		auto.default = '1';

		var interval = sub.option(form.Value, 'update_interval', _('Interval (sec)'),
			_('How often to refresh the subscription.'));
		interval.depends('auto_update', '1');
		interval.datatype = 'uinteger';
		interval.default = '86400';

		var btn = sub.option(form.Button, '_update', _('Update now'));
		btn.inputtitle = _('Fetch subscription');
		btn.inputstyle = 'apply';
		btn.onclick = function() {
			var typed = url.formvalue('subscription') || '';
			if (typed === '') {
				ui.addNotification(null, E('p', _('Enter a subscription URL first.')), 'warning');
				return Promise.resolve();
			}
			ui.showModal(_('Fetching subscription…'), [ E('p', { 'class': 'spinning' }, _('Contacting server')) ]);
			return callSubUpdate(typed).then(function(res) {
				ui.hideModal();
				notifyResult(res);
				if (!(res && res.error))
					window.setTimeout(function() { window.location.reload(); }, 600);
			}).catch(function(e) {
				ui.hideModal();
				ui.addNotification(null, E('p', _('Fetch error: ') + e), 'error');
			});
		};

		var srv = m.section(form.GridSection, 'server', _('Manual servers'),
			_('Add servers by hand, or reorder fetched ones. Lower priority connects first; if unreachable, the next is used.'));
		srv.addremove = true;
		srv.anonymous = true;
		srv.sortable = true;

		srv.option(form.Value, 'tag', _('Name'));
		srv.option(form.Value, 'address', _('Address'));
		var port = srv.option(form.Value, 'port', _('Port'));
		port.datatype = 'port';
		var sec = srv.option(form.ListValue, 'security', _('Security'));
		sec.value('reality', 'Reality');
		sec.value('tls', 'TLS');
		sec.value('none', _('None'));

		return m.render();
	},

	// Save & Apply: persist (incl. URL) then fetch+validate the subscription.
	handleSaveApply: function(ev, mode) {
		var self = this;
		return this.handleSave(ev).then(function() {
			return callSubUpdate('').then(function(res) {
				notifyResult(res);
			});
		});
	}
});
