'use strict';
'require baseclass';
'require view.monkey-business.kit.sheet as sheet';

return baseclass.extend({
	run: function(title, text, work) {
		var s = sheet.open({
			title: title,
			body: E('div', { 'class': 'mb-muted', 'aria-busy': 'true' }, [ text ]),
			closable: false,
			locked: function() { return true; }
		});
		return Promise.resolve().then(work).finally(s.close);
	}
});
