'use strict';
'require baseclass';

function quote(name) {
	return '“' + name + '”';
}

function serversGone(count) {
	if (count === 0)
		return _('It has no servers.');
	if (count === 1)
		return _('Its 1 server is removed with it.');
	return _('Its %d servers are removed with it.').format(count);
}

return baseclass.extend({
	deleteSub: function(o) {
		var body = serversGone(o.count) + ' ' + _('Manual servers stay.');
		if (o.next)
			body += ' ' + _('It is the active subscription — %s becomes active.').format(quote(o.next));
		return { title: _('Delete %s?').format(quote(o.name)), body: body };
	},

	deleteServer: function(o) {
		var body = o.sub
			? _('It comes back with the next update of %s. To keep it out of rotation, turn it off instead.').format(quote(o.sub))
			: _('It is a manual server, so it is removed for good. To bring it back, add its link again.');
		return { title: _('Delete %s?').format(quote(o.name)), body: body };
	}
});
