'use strict';
'require baseclass';
'require ui';

return baseclass.extend({
	show: function(text, level) {
		ui.addNotification(null, E('p', {}, [ text ]), level);
	}
});
