'use strict';
'require baseclass';
'require view.monkey-business.api as api';
'require view.monkey-business.util as util';
'require view.monkey-business.kit.notify as notice';

var TRIES = 330;
var STEP_MS = 3000;
var GRACE = 4;

function poll() {
	var tries = 0;
	var started = false;
	var seen = { state: 'updating' };
	function step() {
		return api.hysteriaStatus().catch(function() { return null; }).then(function(s) {
			var running = !s || s.state === 'updating';
			started = started || !!s && s.state === 'updating';
			if (!running && (started || tries >= GRACE))
				return s;
			if (running)
				seen = s || seen;
			if (++tries >= TRIES)
				return seen;
			return util.sleep(STEP_MS).then(step);
		});
	}
	return step();
}

function reason(s) {
	return String((s && s.state) || '').replace(/^error:\s*/, '');
}

function finished(s) {
	if (s && s.state === 'updating') {
		notice.show(_('The download is still running — reload the page later to see the result.'), 'warning');
		return s;
	}
	var ok = s && s.installed;
	notice.show(ok ? _('hysteria client installed.') : _('Install failed: ') + reason(s), ok ? 'info' : 'warning');
	return s;
}

function watch() {
	return poll().then(finished);
}

return baseclass.extend({
	run: function(onStart) {
		return api.hysteriaInstall().then(function(res) {
			if (res && res.error) {
				notice.show(_('Install failed: ') + res.error, 'error');
				return null;
			}
			onStart();
			return watch();
		}, function(e) {
			notice.show(_('Install failed: ') + e, 'error');
			return null;
		});
	},

	watch: watch
});
