'use strict';
'require baseclass';
'require view.monkey-business.api as api';
'require view.monkey-business.util as util';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.kit.notify as notice';
'require view.monkey-business.kit.guard as guard';

style.add('dash-toggle', [
	'.mb .mb-btn.mb-dash-toggle{padding:8px 16px;font-weight:600;white-space:nowrap}',
	'.mb .mb-btn.mb-dash-stop{background:var(--mb-stop);color:var(--mb-stop-text)}',
	'.mb .mb-btn.mb-dash-stop,.mb .mb-btn.mb-dash-stop:hover{border-color:var(--mb-stop-edge)!important}',
	style.MOBILE + '{.mb .mb-btn.mb-dash-toggle{width:100%;padding:11px 0}}'
].join(''));

var TRIES = 12;
var STEP_MS = 1500;

function untilRunning() {
	var tries = 0;
	function step() {
		return api.status().catch(function() { return {}; }).then(function(st) {
			if (st && st.running)
				return true;
			if (++tries >= TRIES)
				return false;
			return util.sleep(STEP_MS).then(step);
		});
	}
	return step();
}

function turnOn() {
	return api.serviceToggle(true).then(function(res) {
		if (res && res.error)
			return notice.show(_('Connect failed: ') + res.error, 'error');
		return untilRunning().then(function(ok) {
			if (!ok)
				notice.show(_('Service did not come up — check logs (logread | grep xray).'), 'warning');
		});
	}).catch(notice.fail(_('Connect error: ')));
}

function turnOff() {
	return api.serviceToggle(false).catch(notice.fail(_('Turn off failed: ')));
}

return baseclass.extend({
	render: function(o) {
		var on = false;
		var blocked = false;
		var busy = false;
		var btn = E('button', { 'type': 'button' });

		function paint() {
			btn.className = 'mb-btn mb-dash-toggle ' + (on ? 'mb-dash-stop' : 'mb-btn-primary');
			btn.disabled = o.readonly || blocked;
			btn.setAttribute('aria-disabled', busy ? 'true' : 'false');
			if (blocked)
				btn.setAttribute('aria-describedby', 'mb-dash-geoneed');
			else
				btn.removeAttribute('aria-describedby');
			if (!busy)
				btn.textContent = on ? _('Turn off') : _('Turn on');
		}

		btn.addEventListener('click', function() {
			if (btn.disabled)
				return;
			guard.run(btn, function() {
				busy = true;
				btn.textContent = on ? _('Turning off…') : _('Connecting…');
				paint();
				return (on ? turnOff() : turnOn()).then(o.onDone).finally(function() {
					busy = false;
					paint();
				});
			});
		});

		return {
			node: btn,
			update: function(st, geoMissing) {
				on = !!st.enabled;
				blocked = !on && geoMissing;
				paint();
			}
		};
	}
});
