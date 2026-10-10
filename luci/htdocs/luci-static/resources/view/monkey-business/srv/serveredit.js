'use strict';
'require baseclass';
'require view.monkey-business.api as api';
'require view.monkey-business.store as store';
'require view.monkey-business.kit.confirm as confirm';
'require view.monkey-business.model.servers as model';
'require view.monkey-business.model.serverwrite as serverwrite';
'require view.monkey-business.model.confirmtext as confirmtext';
'require view.monkey-business.srv.serversheet as serversheet';

var LOST = {
	not_found: _('The router has no saved link for this server yet. Paste its link again.'),
	not_manual: _('Only manual servers can be edited.')
};

return baseclass.extend({
	create: function(o) {
		var saved = {};
		var fresh = {};
		var opening = false;

		function write(sid, flat, name, link) {
			serverwrite.ops(store.get(sid), flat, name).forEach(function(op) {
				store.set(sid, op[0], op[1]);
			});
			fresh[sid] = serverwrite.relink(link, store.get(sid, 'tag'));
			o.onChange();
		}

		function known(sid) {
			return fresh[sid] || saved[sid];
		}

		function linkOf(sid) {
			if (known(sid))
				return Promise.resolve({ link: known(sid) });
			return api.serverLink(sid).then(function(res) {
				if (res && res.ok)
					return { link: res.link };
				return { note: LOST[res && res.error] || _('Could not read the link: %s').format(res && res.error) };
			}, function(e) {
				return { note: _('Could not read the link: %s').format(e && e.message || e) };
			});
		}

		function off(sid) {
			store.set(sid, 'disabled', '1');
			o.onChange();
		}

		function drop(sid) {
			store.remove(sid);
			delete fresh[sid];
			o.onChange();
		}

		function remove(sid) {
			var s = store.get(sid);
			var sub = o.subName(s);
			var text = confirmtext.deleteServer({ name: model.title(s), sub: sub });
			var actions = [ { label: _('Cancel'), kind: 'cancel', value: null } ];
			if (sub && !model.isOff(s))
				actions.push({ label: _('Turn off'), kind: 'second', value: off });
			actions.push({ label: _('Delete'), kind: 'danger', value: drop });
			return confirm.ask({ title: text.title, body: text.body, actions: actions, back: o.back(sid, 'mb-srow-del') }).then(function(run) {
				if (run)
					run(sid);
			});
		}

		function add() {
			serversheet.open({
				sid: '',
				back: o.back('', 'mb-srvs-add'),
				onSave: function(flat, name, link) { write(store.add('server'), flat, name, link); }
			});
		}

		function edit(sid) {
			if (opening)
				return Promise.resolve();
			opening = true;
			return linkOf(sid).then(function(got) {
				if (o.blocked())
					return;
				serversheet.open({
					sid: sid,
					back: o.back(sid, 'mb-srow-edit'),
					link: got.link,
					note: got.note,
					onSave: function(flat, name, link) { write(sid, flat, name, link); },
					onDelete: function() { remove(sid); }
				});
			}).finally(function() {
				opening = false;
			});
		}

		return {
			add: add,
			edit: edit,
			remove: remove,
			saved: function(names) {
				Object.keys(fresh).forEach(function(sid) { saved[names[sid] || sid] = fresh[sid]; });
				fresh = {};
			},
			reset: function() { fresh = {}; },
			forget: function() { saved = {}; fresh = {}; }
		};
	}
});
