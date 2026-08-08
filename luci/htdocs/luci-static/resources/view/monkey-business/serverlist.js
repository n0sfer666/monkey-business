'use strict';
'require baseclass';
'require rpc';
'require ui';

// Таблица серверов на дашборде (read-only) + разовый замер latency.
var callPing = rpc.declare({ object: 'monkey-business', method: 'servers_ping' });

return baseclass.extend({
	render: function(servers) {
		// tag приходит из подписки (внешний источник) -> не строим CSS-селектор по нему.
		// Держим ссылки на ping-ячейки в map по tag и обновляем напрямую.
		var pingCells = {};
		var rows = (servers || []).map(function(s) {
			var pingTd = E('td', { 'class': 'td' }, [ '—' ]);
			pingCells[s.tag] = pingTd;
			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td' }, [ '' + (s.priority != null ? s.priority : '-') ]),
				E('td', { 'class': 'td' }, [ s.tag ]),
				E('td', { 'class': 'td' }, [ s.address + ':' + s.port ]),
				// insecure=1 из подписки отключает проверку сертификата — это обязано быть видно:
				// иначе такой сервер выглядит ровно как проверяемый.
				E('td', { 'class': 'td' }, [ (s.protocol || 'vless') + ' / ' + s.security +
					(s.insecure ? _(' (insecure)') : '') ]),
				pingTd
			]);
		});

		var table = E('table', { 'class': 'table' }, [
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, [ _('Prio') ]),
				E('th', { 'class': 'th' }, [ _('Name') ]),
				E('th', { 'class': 'th' }, [ _('Address') ]),
				E('th', { 'class': 'th' }, [ _('Protocol / security') ]),
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
							var cell = pingCells[r.tag];
							if (cell)
								cell.textContent = (r.latency_ms != null) ? (r.latency_ms + ' ms') : _('down');
						});
					}).catch(function(e) {
						ui.addNotification(null, E('p', _('Latency test failed: ') + e), 'error');
					});
				})
			}, [ _('Test latency') ]),
			table
		]);
	}
});
