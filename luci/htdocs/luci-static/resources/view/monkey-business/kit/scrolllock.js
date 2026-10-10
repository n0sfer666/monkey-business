'use strict';
'require baseclass';

var depth = 0;
var saved = null;

function hold() {
	var html = document.documentElement;
	var body = document.body;
	var gap = window.innerWidth - html.clientWidth;
	saved = { html: html.style.overflow, body: body.style.overflow, pad: body.style.paddingRight };
	if (gap > 0)
		body.style.paddingRight = (parseFloat(getComputedStyle(body).paddingRight) + gap) + 'px';
	html.style.overflow = 'hidden';
	body.style.overflow = 'hidden';
}

function free() {
	document.documentElement.style.overflow = saved.html;
	document.body.style.overflow = saved.body;
	document.body.style.paddingRight = saved.pad;
	saved = null;
}

return baseclass.extend({
	lock: function() {
		var held = true;
		if (depth++ === 0)
			hold();
		return function release() {
			if (!held)
				return;
			held = false;
			if (--depth === 0)
				free();
		};
	}
});
