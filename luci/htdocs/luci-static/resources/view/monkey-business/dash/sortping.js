'use strict';
'require baseclass';
'require uci';
'require view.monkey-business.api as api';
'require view.monkey-business.store as store';
'require view.monkey-business.subs as subs';
'require view.monkey-business.model.order as order';
'require view.monkey-business.dash.unsaved as unsaved';

function sidMap(list) {
	var out = {};
	list.forEach(function(s) { out[subs.serverId(s)] = s['.name']; });
	return out;
}

function placed(all, group, ranked) {
	var at = 0;
	return all.map(function(sid) { return group.indexOf(sid) >= 0 ? ranked[at++] : sid; });
}

function save(sids, enabled) {
	return uci.callOrder(store.CONF, sids).then(function() {
		return store.commit();
	}).then(function() {
		return store.reset();
	}).then(function() {
		return enabled ? api.configApply() : { skipped: 'disabled' };
	}).then(function(res) {
		return (res && res.error) ? { apply_error: res.error } : res;
	});
}

function sort(ids, rankOf, enabled) {
	return unsaved.check(true).then(function(err) {
		if (err)
			return { error: err };
		return store.reset().then(function() {
			var servers = store.sections('server');
			var byId = sidMap(servers);
			var wanted = {};
			ids.forEach(function(id) { if (byId[id]) wanted[byId[id]] = id; });
			var group = servers.map(function(s) { return s['.name']; }).filter(function(sid) { return wanted[sid]; });
			var ranked = order.sorted(group, function(sid) { return rankOf(wanted[sid]); });
			if (ranked.join(' ') === group.join(' '))
				return { unchanged: true };
			var all = store.sections().map(function(s) { return s['.name']; });
			return save(placed(all, group, ranked), enabled);
		});
	});
}

return baseclass.extend({
	sort: sort
});
