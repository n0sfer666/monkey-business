'use strict';
'require baseclass';
'require view.monkey-business.store as store';
'require view.monkey-business.kit.notify as notice';

function saveErr(e) {
	throw new Error(_('Save failed: ') + (e && e.message || e));
}

function commit() {
	return store.commit().catch(saveErr);
}

return baseclass.extend({
	create: function(o) {
		function reload() {
			return o.onReload().catch(notice.fail(_('Reload failed: ')));
		}

		return function(next) {
			return store.save(o.onSaved).then(function() {
				return commit().then(next).finally(reload);
			}, function(e) {
				o.onFail();
				saveErr(e);
			});
		};
	}
});
