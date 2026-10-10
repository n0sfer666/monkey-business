'use strict';
'require baseclass';

var stack = [];
var muted = [];

function key(ev) {
	var top = stack[stack.length - 1];
	if (ev.defaultPrevented || ev.isComposing || ev.keyCode === 229)
		return;
	if (ev.key === 'Tab')
		return top.tab(ev);
	if (ev.key !== 'Escape')
		return;
	ev.preventDefault();
	top.dismiss();
}

function settle() {
	muted.forEach(function(el) { el.inert = false; });
	muted = [];
	if (!stack.length)
		return;
	var node = stack[stack.length - 1].node;
	muted = Array.prototype.filter.call(document.body.children, function(el) {
		return el !== node && !el.inert;
	});
	muted.forEach(function(el) { el.inert = true; });
}

return baseclass.extend({
	push: function(layer) {
		if (!stack.length)
			document.addEventListener('keydown', key);
		stack.push(layer);
		settle();
		return function pop() {
			var at = stack.indexOf(layer);
			if (at < 0)
				return false;
			stack.splice(at, 1);
			settle();
			if (!stack.length)
				document.removeEventListener('keydown', key);
			return at === stack.length;
		};
	}
});
