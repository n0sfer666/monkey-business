'use strict';
'require baseclass';

return baseclass.extend({
	render: function(o) {
		var btn = E('button', { 'type': 'button', 'class': 'mb-btn ' + (o.cls || '') }, [ o.label ]);
		btn.addEventListener('click', function() {
			btn.disabled = true;
			btn.textContent = o.busy;
			Promise.resolve(o.run()).finally(function() {
				btn.disabled = false;
				btn.textContent = o.label;
			});
		});
		return btn;
	}
});
