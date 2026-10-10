'use strict';
'require baseclass';

var KEEP = [ 'disabled' ];

function value(v) {
	return (v == null || String(v) === '') ? null : String(v);
}

function ops(current, flat, name) {
	var want = Object.assign({}, flat);
	if (name)
		want.tag = name;
	var out = Object.keys(want).map(function(k) { return [ k, value(want[k]) ]; });
	Object.keys(current || {}).forEach(function(k) {
		if (k.charAt(0) !== '.' && !(k in want) && KEEP.indexOf(k) < 0)
			out.push([ k, null ]);
	});
	return out;
}

function relink(link, tag) {
	var cut = link.indexOf('#');
	return (cut < 0 ? link : link.slice(0, cut)) + '#' + encodeURIComponent(tag || '');
}

return baseclass.extend({
	ops: ops,
	relink: relink
});
