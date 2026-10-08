'use strict';
'require baseclass';
'require rpc';
'require ui';

var callUciApply = rpc.declare({ object: 'uci', method: 'apply', params: ['rollback'], reject: true });

return baseclass.extend({
	apply: function() {
		return callUciApply(false).then(function() { ui.changes.setIndicator(0); });
	}
});
