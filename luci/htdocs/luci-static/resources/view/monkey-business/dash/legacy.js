'use strict';
'require baseclass';
'require view.monkey-business.kit.sheet as sheet';

return baseclass.extend({
	open: function(title, body, onClose) {
		return sheet.open({
			title: title,
			body: E('div', { 'class': 'mb-dash-legacy' }, [ body ]),
			width: '720px',
			onClose: onClose
		});
	}
});
