'use strict';
'require baseclass';

var MIN = 10;
var MAX = 120;
var DEFAULT = 60;

function clamp(minutes) {
	var n = parseInt(minutes, 10);
	if (isNaN(n) || n <= 0)
		return 0;
	return Math.min(MAX, Math.max(MIN, n));
}

function fromConfig(auto, seconds) {
	if (auto !== '1')
		return 0;
	var n = parseInt(seconds, 10);
	return isNaN(n) || n <= 0 ? DEFAULT : clamp(Math.round(n / 60));
}

function toConfig(minutes) {
	var n = clamp(minutes);
	return n === 0 ? { auto_update: '0' } : { auto_update: '1', update_interval: String(n * 60) };
}

function text(minutes) {
	var n = clamp(minutes);
	if (n === 0)
		return _('off');
	var h = Math.floor(n / 60);
	var m = n % 60;
	if (h === 0)
		return _('every %d min').format(m);
	return m ? _('every %d h %d min').format(h, m) : _('every %d h').format(h);
}

function note(draft) {
	var n = parseInt(draft, 10) || 0;
	if (n === 0)
		return { text: _('0 = off · auto-update disabled'), warn: false };
	if (n < MIN)
		return { text: _('Minimum is %d min, will be saved as %d').format(MIN, MIN), warn: true };
	if (n > MAX)
		return { text: _('Maximum is %d min, will be saved as %d').format(MAX, MAX), warn: true };
	return { text: _('Minutes · 0 = off · %d–%d · Enter saves, Esc cancels').format(MIN, MAX), warn: false };
}

function digits(raw) {
	return String(raw || '').replace(/[^0-9]/g, '').slice(0, 3);
}

return baseclass.extend({
	MIN: MIN,
	MAX: MAX,
	DEFAULT: DEFAULT,
	clamp: clamp,
	fromConfig: fromConfig,
	toConfig: toConfig,
	text: text,
	note: note,
	digits: digits
});
