'use strict';
'require baseclass';

var LEGACY_SUB = 'subscription';

function serverSub(s) {
	if (s == null || s.source !== 'subscription')
		return null;
	return s.sub ? s.sub : LEGACY_SUB;
}

function find(subs, id) {
	return (subs || []).filter(function(sub) { return sub.id === id; })[0] || null;
}

function name(subs, id) {
	var sub = find(subs, id);
	return sub ? sub.name : (id || '');
}

return baseclass.extend({
	LEGACY_SUB: LEGACY_SUB,
	serverSub: serverSub,
	find: find,
	name: name
});
