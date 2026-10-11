'use strict';
'require baseclass';

function run(btn, fn) {
	if (btn.getAttribute('aria-disabled') === 'true')
		return Promise.resolve(null);
	btn.setAttribute('aria-disabled', 'true');
	btn.setAttribute('aria-busy', 'true');
	return new Promise(function(resolve) { resolve(fn()); }).finally(function() {
		btn.removeAttribute('aria-disabled');
		btn.removeAttribute('aria-busy');
	});
}

return baseclass.extend({
	run: run
});
