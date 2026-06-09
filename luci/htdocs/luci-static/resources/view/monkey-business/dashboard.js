'use strict';
'require view';
'require rpc';
'require ui';
'require uci';

var callStatus = rpc.declare({ object: 'monkey-business', method: 'status' });
var callServers = rpc.declare({ object: 'monkey-business', method: 'servers_list' });
var callPing = rpc.declare({ object: 'monkey-business', method: 'servers_ping' });
var callApply = rpc.declare({ object: 'monkey-business', method: 'config_apply' });
var callGeo = rpc.declare({ object: 'monkey-business', method: 'geo_update' });
var callToggle = rpc.declare({
	object: 'monkey-business', method: 'service_toggle', params: ['enabled']
});

function toGB(bytes) {
	var n = parseFloat(bytes);
	if (isNaN(n) || n <= 0) return 0;
	return n / 1073741824;
}

function fmtDate(epoch) {
	var n = parseInt(epoch, 10);
	if (isNaN(n) || n <= 0) return '-';
	return new Date(n * 1000).toISOString().slice(0, 10);
}

function sleep(ms) {
	return new Promise(function(r) { window.setTimeout(r, ms); });
}

return view.extend({
	load: function() {
		return Promise.all([ callStatus(), callServers(), uci.load('monkey-business') ]);
	},

	// #6 — traffic readout (only if subscription reported it)
	renderTraffic: function(t) {
		if (!t || !t.total || toGB(t.total) <= 0)
			return E([]);
		var used = toGB(t.used_download) + toGB(t.used_upload);
		var total = toGB(t.total);
		var pct = total > 0 ? Math.min(100, Math.round(used / total * 100)) : 0;
		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ _('Subscription traffic') ]),
			E('p', {}, [ used.toFixed(1) + ' / ' + total.toFixed(1) + ' GB (' + pct + '%)' ]),
			E('div', { 'style': 'background:#ddd;border-radius:4px;height:14px;width:100%;max-width:420px;overflow:hidden' }, [
				E('div', { 'style': 'background:' + (pct < 90 ? '#33a02c' : '#e31a1c') + ';height:14px;width:' + pct + '%' }, [])
			]),
			E('p', { 'style': 'color:#888' }, [ _('Expires: ') + fmtDate(t.expire) ])
		]);
	},

	pollUntilRunning: function() {
		var tries = 0;
		function step() {
			return callStatus().then(function(st) {
				if (st.running) return true;
				if (++tries >= 12) return false;
				return sleep(1500).then(step);
			});
		}
		return step();
	},

	// #2 — Turn on actually connects; poll for running; surface errors instead of endless "Starting…"
	handleToggle: function(on) {
		var self = this;
		if (!on)
			return callToggle(false).then(function() { window.location.reload(); });

		ui.showModal(_('Connecting…'), [ E('p', { 'class': 'spinning' }, _('Selecting server and starting Xray')) ]);
		return callToggle(true).then(function(res) {
			if (res && res.error) {
				ui.hideModal();
				ui.addNotification(null, E('p', _('Connect failed: ') + res.error), 'error');
				return;
			}
			return self.pollUntilRunning().then(function(ok) {
				ui.hideModal();
				if (!ok)
					ui.addNotification(null, E('p', _('Service did not come up — check logs (logread | grep xray).')), 'warning');
				window.location.reload();
			});
		}).catch(function(e) {
			ui.hideModal();
			ui.addNotification(null, E('p', _('Connect error: ') + e), 'error');
		});
	},

	renderStatus: function(st) {
		var self = this;
		var on = !!st.enabled, running = !!st.running;
		var label = on ? (running ? _('Connected') : _('Starting…')) : _('Off');
		var color = running ? '#33a02c' : (on ? '#ff7f00' : '#888');

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ _('Status') ]),
			E('p', { 'style': 'font-size:1.4em;color:' + color }, [ label ]),
			E('p', {}, [ _('Server: ') + (st.server || _('none')) ]),
			E('p', {}, [ _('Routing: ') + (st.routing_mode || '-') ]),
			E('button', {
				'class': 'btn cbi-button ' + (on ? 'cbi-button-remove' : 'cbi-button-apply'),
				'click': ui.createHandlerFn(this, function() { return self.handleToggle(!on); })
			}, [ on ? _('Turn off') : _('Turn on') ])
		]);
	},

	// #5 — custom direct/vpn lists (split-tunnel only) + geo databases
	renderRouting: function() {
		var self = this;
		var direct = uci.get('monkey-business', 'global', 'custom_direct') || '';
		var proxy = uci.get('monkey-business', 'global', 'custom_proxy') || '';

		var taDirect = E('textarea', {
			'rows': 6, 'style': 'width:100%;max-width:480px',
			'placeholder': 'example.com\n10.0.0.0/8\ngeosite:category-ru\ngeoip:ru'
		}, [ direct ]);
		var taProxy = E('textarea', {
			'rows': 6, 'style': 'width:100%;max-width:480px',
			'placeholder': 'blocked.example\ngeosite:google\ngeoip:netflix'
		}, [ proxy ]);

		var save = E('button', {
			'class': 'btn cbi-button cbi-button-apply',
			'click': ui.createHandlerFn(this, function() {
				uci.set('monkey-business', 'global', 'custom_direct', taDirect.value);
				uci.set('monkey-business', 'global', 'custom_proxy', taProxy.value);
				return uci.save().then(function() {
					return callApply().then(function(res) {
						if (res && res.error)
							ui.addNotification(null, E('p', _('Apply failed: ') + res.error), 'warning');
						else
							ui.addNotification(null, E('p', _('Routing rules applied.')), 'info');
					});
				});
			})
		}, [ _('Save & Apply') ]);

		var geoBtn = E('button', {
			'class': 'btn cbi-button',
			'click': ui.createHandlerFn(this, function() {
				ui.showModal(_('Updating geo databases…'), [ E('p', { 'class': 'spinning' }, _('Downloading geoip/geosite')) ]);
				return callGeo().then(function(res) {
					ui.hideModal();
					var ok = res && (res.status === 'ok' || res.present);
					ui.addNotification(null, E('p', ok ? _('Geo databases updated.') : (_('Geo update failed: ') + ((res && res.detail) || ''))), ok ? 'info' : 'warning');
				}).catch(function(e) { ui.hideModal(); ui.addNotification(null, E('p', '' + e), 'error'); });
			})
		}, [ _('Update geo databases') ]);

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ _('Custom routing (split-tunnel)') ]),
			E('p', { 'style': 'color:#888' }, [ _('One entry per line: domain, IP/CIDR, geosite:NAME or geoip:NAME. Active only in split-tunnel modes (not "Everything via VPN").') ]),
			E('div', { 'style': 'display:flex;gap:24px;flex-wrap:wrap' }, [
				E('div', {}, [ E('strong', {}, [ _('Direct (bypass VPN)') ]), taDirect ]),
				E('div', {}, [ E('strong', {}, [ _('Via VPN') ]), taProxy ])
			]),
			E('p', { 'style': 'margin-top:8px' }, [ save, ' ', geoBtn ])
		]);
	},

	renderServers: function(servers) {
		var rows = (servers || []).map(function(s) {
			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td' }, [ '' + (s.priority != null ? s.priority : '-') ]),
				E('td', { 'class': 'td' }, [ s.tag ]),
				E('td', { 'class': 'td' }, [ s.address + ':' + s.port ]),
				E('td', { 'class': 'td' }, [ s.security ]),
				E('td', { 'class': 'td', 'data-ping': s.tag }, [ '—' ])
			]);
		});

		var table = E('table', { 'class': 'table' }, [
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, [ _('Prio') ]),
				E('th', { 'class': 'th' }, [ _('Name') ]),
				E('th', { 'class': 'th' }, [ _('Address') ]),
				E('th', { 'class': 'th' }, [ _('Security') ]),
				E('th', { 'class': 'th' }, [ _('Ping') ])
			])
		].concat(rows));

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ _('Servers') ]),
			E('button', {
				'class': 'btn cbi-button',
				'click': ui.createHandlerFn(this, function() {
					return callPing().then(function(res) {
						(res.results || []).forEach(function(r) {
							var cell = document.querySelector('[data-ping="' + r.tag + '"]');
							if (cell)
								cell.textContent = (r.latency_ms != null) ? (r.latency_ms + ' ms') : _('down');
						});
					});
				})
			}, [ _('Test latency') ]),
			table
		]);
	},

	render: function(data) {
		var st = data[0] || {};
		var servers = (data[1] || {}).servers || [];
		return E('div', {}, [
			this.renderTraffic(st.traffic),
			this.renderStatus(st),
			this.renderRouting(),
			this.renderServers(servers)
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
