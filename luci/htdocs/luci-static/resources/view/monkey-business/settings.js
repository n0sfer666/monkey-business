'use strict';
'require view';
'require form';
'require rpc';
'require ui';
'require uci';

var callApply = rpc.declare({ object: 'monkey-business', method: 'config_apply' });

return view.extend({
	render: function() {
		var m = new form.Map('monkey-business', _('Settings'),
			_('Each option has a hint explaining what it does. Defaults are safe.'));

		var g = m.section(form.NamedSection, 'global', 'global', _('General'));

		var mode = g.option(form.ListValue, 'routing_mode', _('Routing mode'),
			_('What goes through the VPN. "Bypass local" sends your region (RU/CN) and private addresses direct, everything else through the tunnel.'));
		mode.value('bypass-local', _('Bypass local (recommended)'));
		mode.value('gfwlist', _('Only blocked via VPN'));
		mode.value('global', _('Everything via VPN'));
		mode.default = 'bypass-local';

		var region = g.option(form.ListValue, 'local_region', _('Local region'),
			_('Region treated as "local" for direct routing (geoip/geosite). Pick "Other" if your region has no geo preset — then you drive the split yourself with the custom Direct/Via-VPN lists on the Dashboard; private stays direct and the rest follows the routing mode.'));
		region.value('ru', 'Russia');
		region.value('cn', 'China');
		region.value('ir', 'Iran');
		region.value('other', _('Other — no geo preset (custom lists drive routing)'));
		region.default = 'ru';

		var ks = g.option(form.Flag, 'kill_switch', _('Kill-switch'),
			_('Fail-closed: LAN traffic to non-local destinations is dropped instead of leaking direct whenever it is not carried by the tunnel (Xray down, rule gap, or non-proxied traffic such as ICMP). Disable for a direct fallback when the tunnel is down (less safe). Local-region and private traffic are unaffected.'));
		ks.default = '1';

		var v6 = g.option(form.Flag, 'ipv6_block', _('Block IPv6'),
			_('Disable IPv6 for clients so traffic cannot leak around the IPv4 tunnel.'));
		v6.default = '1';

		var port = g.option(form.Value, 'tproxy_port', _('TPROXY port'),
			_('Local transparent-proxy port for the Xray inbound. Change only on conflicts.'));
		port.datatype = 'port';
		port.default = '12345';

		var log = g.option(form.ListValue, 'log_level', _('Log level'));
		[ 'none', 'error', 'warning', 'info', 'debug' ].forEach(function(l) { log.value(l); });
		log.default = 'warning';

		var d = m.section(form.NamedSection, 'dns', 'dns', _('DNS'));

		var dmode = d.option(form.ListValue, 'mode', _('DNS mode'),
			_('"Split" resolves local domains directly and foreign ones over DoH in the tunnel — fast and leak-resistant.'));
		dmode.value('split', _('Split (recommended)'));
		dmode.value('doh', _('All over DoH'));
		dmode.default = 'split';

		var direct = d.option(form.Value, 'direct_dns', _('Direct DNS'),
			_('Resolver for local-region domains (queried directly).'));
		direct.default = '77.88.8.8';

		var doh = d.option(form.Value, 'doh_url', _('DoH URL'),
			_('DNS-over-HTTPS endpoint for everything routed through the VPN.'));
		doh.default = 'https://1.1.1.1/dns-query';

		var a = m.section(form.NamedSection, 'anti_dpi', 'anti_dpi', _('Anti-DPI'));

		var fp = a.option(form.ListValue, 'default_fingerprint', _('TLS fingerprint'),
			_('Mimic a real browser TLS fingerprint (uTLS) to evade DPI.'));
		[ 'chrome', 'firefox', 'safari', 'edge', 'random' ].forEach(function(x) { fp.value(x); });
		fp.default = 'chrome';

		var pad = a.option(form.Flag, 'xhttp_padding', _('XHTTP padding'),
			_('Add random padding to XHTTP packets to obscure traffic size patterns.'));
		pad.default = '0';

		return m.render();
	},

	handleSaveApply: function(ev, mode) {
		// handleSave только стейджит -> нужен uci.apply() (commit), иначе config_apply читает
		// старый UCI и изменения висят в "Unsaved Changes".
		return this.handleSave(ev).then(function() {
			return uci.apply();
		}).then(function() {
			return callApply();
		}).then(function(res) {
			if (res && res.error)
				ui.addNotification(null, E('p', _('Apply failed: ') + res.error), 'warning');
			else
				ui.addNotification(null, E('p', _('Configuration applied.')), 'info');
		}).catch(function(e) {
			ui.addNotification(null, E('p', _('Apply failed: ') + e), 'error');
		});
	}
});
