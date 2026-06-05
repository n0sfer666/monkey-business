'use strict';
'require view';
'require form';
'require rpc';
'require ui';

var callSubUpdate = rpc.declare({
	object: 'monkey-business', method: 'subscription_update', params: ['url']
});

return view.extend({
	render: function() {
		var m = new form.Map('monkey-business', _('Servers'),
			_('Subscription (VPNON) and manual servers.'));

		var sub = m.section(form.NamedSection, 'subscription', 'subscription',
			_('Subscription'));

		var url = sub.option(form.Value, 'url', _('Subscription URL'),
			_('VPNON subscription link. Servers are fetched and refreshed automatically.'));
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
			return callSubUpdate('').then(function(res) {
				if (res && res.error)
					ui.addNotification(null, E('p', _('Update failed: ') + res.error), 'warning');
				else
					ui.addNotification(null, E('p', _('Added servers: ') + (res.added || 0)), 'info');
			});
		};

		var srv = m.section(form.GridSection, 'server', _('Manual servers'),
			_('Add servers by hand (vless:// link fields).'));
		srv.addremove = true;
		srv.anonymous = true;

		srv.option(form.Value, 'tag', _('Name'));
		srv.option(form.Value, 'address', _('Address'));
		var port = srv.option(form.Value, 'port', _('Port'));
		port.datatype = 'port';
		var sec = srv.option(form.ListValue, 'security', _('Security'));
		sec.value('reality', 'Reality');
		sec.value('tls', 'TLS');
		sec.value('none', _('None'));

		return m.render();
	}
});
