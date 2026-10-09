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

return baseclass.extend({
	pending: function(state, conf) {
		if (filled(state.creates[conf]) || filled(state.deletes[conf]))
			return true;
		if (state.reorder && state.reorder[conf])
			return true;
		return changed(state.changes[conf], state.values[conf]);
	}
});
