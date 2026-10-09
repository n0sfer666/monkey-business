'use strict';
'require baseclass';
'require rpc';
'require ui';
'require view.monkey-business.subs as subs';
'require view.monkey-business.icons as icons';
'require view.monkey-business.pingtext as pingtext';

var callPing = rpc.declare({ object: 'monkey-business', method: 'servers_ping' });
var callSubPing = rpc.declare({ object: 'monkey-business', method: 'subscription_ping', params: ['sub'] });
var callServerPing = rpc.declare({ object: 'monkey-business', method: 'server_ping', params: ['id'] });

var COLUMNS = 6;

function nameText(s, multi) {
	var marks = [];
	if (multi && s.sub == null)
		marks.push(_('manual'));
	if (s.disabled)
		marks.push(_('off'));
	return marks.length ? s.tag + ' · ' + marks.join(' · ') : s.tag;
}

function groupKey(s) {
	return s.reserve ? s.sub : '';
}

function groupTitle(key, st) {
	if (key === '')
		return _('Active: ') + subs.name(st.subscriptions, st.active_sub);
	return _('Reserve: ') + subs.name(st.subscriptions, key);
}

return baseclass.extend({
	render: function(servers, st) {
		var multi = (st.subscriptions || []).length > 1;
		var cells = {};

		function ping(call) {
			return call.then(function(res) {
				if (res && res.error)
					return ui.addNotification(null, E('p', {}, [ _('Latency test failed: ') + res.error ]), 'warning');
				pingtext.results(res).forEach(function(r) {
					var cell = cells[r.id];
					if (cell)
						cell.textContent = pingtext.text(r.latency_ms, r.na, r.auto_disabled);
				});
			}).catch(function(e) {
				ui.addNotification(null, E('p', {}, [ _('Latency test failed: ') + e ]), 'error');
			});
		}

		function pingButton(label, run, hint) {
			return icons.button('ping', label, ui.createHandlerFn(null, run), hint);
		}

		var manualIds = (servers || []).filter(function(s) { return s.sub == null; })
			.map(function(s) { return s.id; });

		function pingGroup(key) {
			if (key !== '')
				return ping(callSubPing(key));
			return Promise.all([ ping(callSubPing(st.active_sub)) ].concat(manualIds.map(function(id) {
				return ping(callServerPing(id));
			})));
		}

		function groupRow(key) {
			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td', 'colspan': COLUMNS }, [
					E('strong', {}, [ groupTitle(key, st) ]), ' ',
					pingButton(_('Ping'), function() { return pingGroup(key); })
				])
			]);
		}

		function serverRow(s) {
			var pingTd = E('td', { 'class': 'td' }, [ pingtext.text(s.latency_ms, s.ping_na, s.auto_disabled) ]);
			cells[s.id] = pingTd;
			return E('tr', { 'class': 'tr', 'style': s.disabled ? 'opacity:.55' : '' }, [
				E('td', { 'class': 'td' }, [ '' + (s.priority != null ? s.priority : '-') ]),
				E('td', { 'class': 'td' }, [ nameText(s, multi) ]),
				E('td', { 'class': 'td' }, [ s.address + ':' + s.port ]),
				// insecure=1 из подписки отключает проверку сертификата — это обязано быть видно:
				// иначе такой сервер выглядит ровно как проверяемый.
				E('td', { 'class': 'td' }, [ (s.protocol || 'vless') + ' / ' + s.security +
					(s.insecure ? _(' (insecure)') : '') ]),
				pingTd,
				E('td', { 'class': 'td' }, [ pingButton('', function() { return ping(callServerPing(s.id)); }, _('Ping')) ])
			]);
		}

		var rows = [];
		var prev = null;
		(servers || []).forEach(function(s) {
			var key = groupKey(s);
			if (multi && key !== prev)
				rows.push(groupRow(key));
			prev = key;
			rows.push(serverRow(s));
		});

		var table = E('table', { 'class': 'table' }, [
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, [ _('Prio') ]),
				E('th', { 'class': 'th' }, [ _('Name') ]),
				E('th', { 'class': 'th' }, [ _('Address') ]),
				E('th', { 'class': 'th' }, [ _('Protocol / security') ]),
				E('th', { 'class': 'th' }, [ _('Ping') ]),
				E('th', { 'class': 'th' }, [])
			])
		].concat(rows));

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ _('Servers') ]),
			pingButton(_('Test latency'), function() { return ping(callPing()); }),
			table
		]);
	}
});
