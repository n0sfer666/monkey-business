'use strict';
'require baseclass';
'require uci';
'require ui';
'require view.monkey-business.api as api';
'require view.monkey-business.model.dirty as dirty';

var CONF = 'monkey-business';

return baseclass.extend({
	CONF: CONF,

	load: function() { return uci.load(CONF); },
	get: function(sid, opt) { return uci.get(CONF, sid, opt); },
	set: function(sid, opt, value) { return uci.set(CONF, sid, opt, value); },
	add: function(type, name) { return uci.add(CONF, type, name); },
	remove: function(sid) { return uci.remove(CONF, sid); },
	move: function(sid1, sid2, after) { return uci.move(CONF, sid1, sid2, after); },
	sections: function(type, cb) { return uci.sections(CONF, type, cb); },

	dirty: function() { return dirty.pending(uci.state, CONF); },
	changes: function() {
		return uci.changes().then(function(c) { return (c && c[CONF]) || []; });
	},
	save: function() { return uci.save(); },

	reset: function() {
		uci.unload(CONF);
		delete uci.state.reorder[CONF];
		return uci.load(CONF);
	},

	commit: function() {
		return api.uciApply(false).then(function() { ui.changes.setIndicator(0); });
	},

	apply: function() {
		var self = this;
		return self.save().then(function() { return self.commit(); });
	}
});
