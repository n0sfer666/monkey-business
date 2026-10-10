'use strict';
'require baseclass';
'require dom';
'require view.monkey-business.api as api';
'require view.monkey-business.store as store';
'require view.monkey-business.subs as subs';
'require view.monkey-business.kit.drag as drag';
'require view.monkey-business.kit.notify as notice';
'require view.monkey-business.kit.refocus as refocus';
'require view.monkey-business.kit.menu as menu';
'require view.monkey-business.model.servers as model';
'require view.monkey-business.model.subs as submodel';
'require view.monkey-business.model.order as order';
'require view.monkey-business.srv.serverrow as serverrow';
'require view.monkey-business.srv.servertiles as servertiles';
'require view.monkey-business.srv.serveredit as serveredit';
'require view.monkey-business.srv.serverhead as serverhead';

var FOCUS = /^mb-(srow|srvs|seg)-|^mb-tile$/;

return baseclass.extend({
	create: function(o) {
		var root = E('section', { 'class': 'mb-panel mb-srvs' });
		var list = E('div', { 'role': 'list', 'aria-label': _('Servers') });
		var st = { filter: 'all', moving: false, picked: null, pinging: false, pings: {}, known: {} };
		var edit = serveredit.create({
			subName: subName, onChange: changed, blocked: function() { return !!root.closest('[inert]'); },
			back: function(sid, cls) { return refocus.near(root, 'data-sid', sid, [ cls, 'mb-srow-more' ], '.mb-srvs-add'); }
		});

		function subList() {
			return store.sections('subscription').map(function(s) { return { id: s['.name'], name: submodel.title(s) }; });
		}

		function subName(s) {
			var id = subs.serverSub(s);
			return id == null ? null : subs.name(subList(), id);
		}

		function all() {
			return model.visible(store.sections('server'), subList().map(function(x) { return x.id; }));
		}

		function ids() {
			return all().map(function(s) { return s['.name']; });
		}

		function pingOf(s) {
			return st.pings[subs.serverId(s)];
		}

		function changed() {
			draw();
			o.onChange();
		}

		function update(results) {
			(results || []).forEach(function(r) {
				st.pings[r.id] = model.pingOf(r);
				st.known[r.id] = true;
			});
		}

		function move(sid, target, after) {
			store.move(sid, target, after);
		}

		function place(sid, target) {
			var r = order.place(ids(), sid, target);
			if (r)
				move(sid, target, r.after);
			changed();
		}

		function step(sid, dir) {
			var target = order.neighbour(ids(), sid, dir);
			if (!target)
				return;
			move(sid, target, dir > 0);
			changed();
		}

		function tap(sid) {
			var from = st.picked;
			st.picked = from == null ? sid : null;
			if (from != null && from !== sid)
				return place(from, sid);
			draw();
		}

		function sort() {
			var now = ids();
			var want = order.sorted(now, function(sid) { return model.rank(pingOf(store.get(sid))); });
			if (want.join() === now.join())
				return notice.show(_('Already in ping order.'), 'info');
			order.chain(want, move);
			changed();
			notice.show(_('Sorted by ping. Press “Save & Apply” to connect in this order.'), 'info');
		}

		function pingAll() {
			if (st.pinging)
				return Promise.resolve();
			st.pinging = true;
			return api.serversPing().then(function(res) {
				if (res && res.error)
					return notice.show(_('Latency test failed: ') + res.error, 'warning');
				update(res && res.results);
			}).catch(notice.fail(_('Latency test failed: '))).finally(function() {
				st.pinging = false;
			}).then(draw);
		}

		function pingOne(sid) {
			var id = subs.serverId(store.get(sid));
			return api.serverPing(id).then(function(r) {
				if (r && r.error)
					return notice.show(_('Ping failed: ') + r.error, 'warning');
				update([ r ]);
				draw();
			}).catch(notice.fail(_('Ping failed: ')));
		}

		function setOff(sid, on) {
			store.set(sid, 'disabled', on ? '1' : '0');
			changed();
		}

		function rows(servers) {
			var movable = st.filter === 'all' && !o.readonly;
			dom.content(list, model.filtered(servers, st.filter).map(function(s) {
				return serverrow.render({
					server: s, n: servers.indexOf(s) + 1, subName: subName(s), ping: model.ping(pingOf(s)), movable: movable,
					pingable: !!st.known[subs.serverId(s)], readonly: o.readonly,
					onStep: step, onOff: setOff, onPing: pingOne, onEdit: edit.edit, onDelete: edit.remove
				});
			}));
			return list;
		}

		function body(servers) {
			if (!servers.length)
				return [ E('div', { 'class': 'mb-srvs-empty mb-muted' }, [ _('No servers yet. Fetch a subscription or add a server by its link.') ]) ];
			if (st.moving)
				return servertiles.render({ servers: servers, picked: st.picked, onTap: tap, ping: function(s) { return model.ping(pingOf(s)); } });
			return [ serverhead.cols(), rows(servers) ];
		}

		function draw() {
			menu.close();
			refocus.around(root, { pattern: FOCUS, attr: 'data-sid', spare: function() { return root.querySelector('.mb-srvs-add'); } }, paint);
		}

		function relist() {
			return api.serversList().then(function(res) {
				update(res && res.servers);
				draw();
			}, function() {});
		}

		function paint() {
			var servers = all();
			var opts = model.filters(servers, subList());
			if (!opts.some(function(f) { return f.value === st.filter; }))
				st.filter = 'all';
			dom.content(root, [ serverhead.render({
				count: servers.length, filters: opts, filter: st.filter, moving: st.moving, pinging: st.pinging, readonly: o.readonly,
				onFilter: function(v) { st.filter = v; st.moving = false; draw(); },
				onGear: function() { st.moving = !st.moving; st.picked = null; draw(); },
				onPingAll: pingAll, onSort: sort, onAdd: edit.add
			}) ].concat(body(servers), [
				E('div', { 'class': 'mb-srvs-foot mb-muted mb-small' }, [
					_('The first server that answers is used, top to bottom. Order and Off apply on Save & Apply.')
				])
			]));
		}

		function relabel() {
			root.querySelectorAll('.mb-srow[data-sid]').forEach(function(row) {
				serverrow.relabel(row, store.get(row.getAttribute('data-sid')), subName);
			});
			serverhead.relabel(root, model.filters(all(), subList()));
		}

		drag.attach(list, { handle: '.mb-srow-grip', key: 'data-sid', onDrop: place });
		update(o.list && o.list.servers);
		draw();

		return {
			node: root,
			draw: draw,
			relabel: relabel,
			forget: edit.forget,
			saved: edit.saved,
			reset: edit.reset,
			relist: relist,
			onPing: function(res) { update(res && res.results); draw(); }
		};
	}
});
