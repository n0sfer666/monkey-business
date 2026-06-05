'use strict';
'require view';
'require rpc';
'require ui';
'require poll';

var callStatus = rpc.declare({ object: 'monkey-business', method: 'status' });
var callServers = rpc.declare({ object: 'monkey-business', method: 'servers_list' });
var callPing = rpc.declare({ object: 'monkey-business', method: 'servers_ping' });
var callToggle = rpc.declare({
	object: 'monkey-business', method: 'service_toggle', params: ['enabled']
});

return view.extend({
	load: function() {
		return Promise.all([ callStatus(), callServers() ]);
	},

	renderStatus: function(st) {
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
				'click': ui.createHandlerFn(this, function() {
					return callToggle(!on).then(function() {
						window.location.reload();
					});
				})
			}, [ on ? _('Turn off') : _('Turn on') ])
		]);
	},

	renderServers: function(servers) {
		var rows = (servers || []).map(function(s) {
			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td' }, [ s.tag ]),
				E('td', { 'class': 'td' }, [ s.address + ':' + s.port ]),
				E('td', { 'class': 'td' }, [ s.security ]),
				E('td', { 'class': 'td', 'data-ping': s.tag }, [ '—' ])
			]);
		});

		var table = E('table', { 'class': 'table' }, [
			E('tr', { 'class': 'tr table-titles' }, [
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
								cell.textContent = (r.latency_ms != null)
									? (r.latency_ms + ' ms') : _('down');
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
			this.renderStatus(st),
			this.renderServers(servers)
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
