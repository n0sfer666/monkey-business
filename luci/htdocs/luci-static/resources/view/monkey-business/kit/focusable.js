'use strict';
'require baseclass';

var SEL = 'button:not([disabled]),input:not([disabled]),select:not([disabled]),textarea:not([disabled]),' +
	'a[href],[tabindex]:not([tabindex="-1"])';

function list(root) {
	return Array.prototype.filter.call(root.querySelectorAll(SEL), function(el) {
		return el.getAttribute('tabindex') !== '-1' && el.getClientRects().length > 0;
	});
}

function before(items, el) {
	return items.filter(function(it) {
		return (it.compareDocumentPosition(el) & Node.DOCUMENT_POSITION_FOLLOWING) !== 0;
	}).length;
}

return baseclass.extend({
	SEL: SEL,

	cycle: function(root, back) {
		var items = list(root);
		var n = items.length;
		var cur = document.activeElement || root;
		var at = items.indexOf(cur);
		var step = back ? -1 : 1;
		var lag = back ? 0 : 1;
		var from = at < 0 ? before(items, cur) - lag : at;
		for (var k = 1; k <= n; k++) {
			var el = items[((from + step * k) % n + n) % n];
			el.focus();
			if (document.activeElement === el)
				return;
		}
		root.focus();
	}
});
