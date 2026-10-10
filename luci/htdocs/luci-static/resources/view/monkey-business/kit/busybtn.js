'use strict';
'require baseclass';

function hold(btn, o) {
	btn.setAttribute('aria-disabled', 'true');
	btn.textContent = o.busy;
}

return baseclass.extend({
	render: function(o) {
		var btn = E('button', { 'type': 'button', 'class': 'mb-btn ' + (o.cls || '') }, [ o.label ]);
		if (o.pending)
			hold(btn, o);
		btn.addEventListener('click', function() {
			if (btn.getAttribute('aria-disabled') === 'true')
				return;
			hold(btn, o);
			Promise.resolve(o.run()).finally(function() {
				btn.removeAttribute('aria-disabled');
				btn.textContent = o.label;
			});
		});
		return btn;
	}
});
