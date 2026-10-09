'use strict';
'require baseclass';
'require form';
'require rpc';
'require ui';
'require uci';
'require view.monkey-business.subs as subs';
'require view.monkey-business.icons as icons';
'require view.monkey-business.pingtext as pingtext';

var CONFIG = 'monkey-business';

var callList = rpc.declare({ object: 'monkey-business', method: 'servers_list' });
var callPing = rpc.declare({ object: 'monkey-business', method: 'servers_ping' });

function notify(text, level) {
	ui.addNotification(null, E('p', {}, [ text ]), level);
}

function idOf(sid) {
	return subs.serverId(uci.get(CONFIG, sid));
}

function rank(p) {
	return (p != null && !p.na && p.ms != null) ? p.ms : Infinity;
}

function byRank(a, b) {
	if (a[0] === b[0])
		return 0;
	return a[0] < b[0] ? -1 : 1;
}

return baseclass.extend({
	load: function() {
		return callList();
	},

	create: function(list) {
		var pings = {};
		var cells = {};

		function show(id) {
			var p = pings[id];
			return p ? pingtext.text(p.ms, p.na, p.off) : '—';
		}

		function store(id, ms, na, off) {
			pings[id] = { ms: ms, na: na, off: off };
			if (cells[id])
				cells[id].textContent = show(id);
		}

		function update(res) {
			pingtext.results(res).forEach(function(r) {
				store(r.id, r.latency_ms, r.na, r.auto_disabled);
			});
		}

		function pingAll() {
			return callPing().then(function(res) {
				if (res && res.error)
					return notify(_('Latency test failed: ') + res.error, 'warning');
				update(res);
			}).catch(function(e) {
				notify(_('Latency test failed: ') + e, 'error');
			});
		}

		function sortRows(sectionEl) {
			var rows = Array.prototype.slice.call(sectionEl.querySelectorAll('tr.cbi-section-table-row[data-sid]'));
			var ranked = rows.map(function(tr) {
				return [ rank(pings[idOf(tr.getAttribute('data-sid'))]), tr ];
			});
			ranked.sort(byRank);
			var prev = null;
			ranked.forEach(function(entry) {
				var tr = entry[1];
				var sid = tr.getAttribute('data-sid');
				tr.parentNode.appendChild(tr);
				if (prev != null)
					uci.move(CONFIG, sid, prev, true);
				prev = sid;
			});
			notify(_('Sorted by ping. Press "Save & Apply" to connect in this order.'), 'info');
		}

		((list && list.servers) || []).forEach(function(s) {
			store(s.id, s.latency_ms, s.ping_na, s.auto_disabled);
		});

		function toolbar(sectionEl) {
			return E('div', { 'class': 'cbi-section-actions' }, [
				icons.button('ping', _('Ping all'), ui.createHandlerFn(null, pingAll)), ' ',
				E('button', {
					'class': 'btn cbi-button',
					'title': _('Fastest first. Unreachable and unmeasured go last.'),
					'click': function() { sortRows(sectionEl); }
				}, [ _('Sort by ping') ])
			]);
		}

		function attach(srv) {
			var col = srv.option(form.DummyValue, '_ping', _('Ping'));
			col.modalonly = false;
			col.renderWidget = function(sid) {
				var id = idOf(sid);
				cells[id] = E('span', {}, [ show(id) ]);
				return cells[id];
			};

			var renderContents = srv.renderContents;
			srv.renderContents = function() {
				var el = renderContents.apply(this, arguments);
				el.insertBefore(toolbar(el), el.querySelector('table'));
				return el;
			};
		}

		return { update: update, attach: attach };
	}
});
