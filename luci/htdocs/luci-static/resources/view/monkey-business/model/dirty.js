'use strict';
'require baseclass';

function filled(map) {
	return !!map && Object.keys(map).length > 0;
}

function same(a, b) {
	return JSON.stringify(a) === JSON.stringify(b);
}

function changed(changes, values) {
	return Object.keys(changes || {}).some(function(sid) {
		var orig = (values || {})[sid] || {};
		return Object.keys(changes[sid]).some(function(opt) {
			return !same(changes[sid][opt], orig[opt]);
		});
	});
}

function typeOf(state, conf, sid) {
	var s = (state.creates[conf] || {})[sid] || (state.values[conf] || {})[sid];
	return s && s['.type'];
}

return baseclass.extend({
	touched: function(state, conf, type) {
		function mine(sid) { return typeOf(state, conf, sid) === type; }
		if (Object.keys(state.creates[conf] || {}).some(mine) || Object.keys(state.deletes[conf] || {}).some(mine))
			return true;
		var changes = state.changes[conf] || {};
		var own = {};
		Object.keys(changes).filter(mine).forEach(function(sid) { own[sid] = changes[sid]; });
		return changed(own, state.values[conf]);
	},


	pending: function(state, conf) {
		if (filled(state.creates[conf]) || filled(state.deletes[conf]))
			return true;
		if (state.reorder && state.reorder[conf])
			return true;
		return changed(state.changes[conf], state.values[conf]);
	}
});
