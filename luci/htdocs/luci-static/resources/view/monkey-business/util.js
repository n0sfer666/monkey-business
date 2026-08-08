'use strict';
'require baseclass';

return baseclass.extend({
	sleep: function(ms) {
		return new Promise(function(r) { window.setTimeout(r, ms); });
	}
});
