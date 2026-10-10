'use strict';
'require baseclass';
'require view.monkey-business.kit.sheetcss as sheetcss';
'require view.monkey-business.kit.focusable as focusable';
'require view.monkey-business.kit.scrolllock as scrolllock';
'require view.monkey-business.kit.layers as layers';
'require view.monkey-business.kit.trigger as trigger';

var CROSS = '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">' +
	'<path d="M6 6l12 12M18 6L6 18"></path></svg>';

var seq = 0;

function vars(o) {
	var out = [];
	if (o.width)
		out.push('--mb-sheet-w:' + o.width);
	if (o.top)
		out.push('--mb-sheet-top:min(' + o.top + ',35vh)');
	if (o.mtop)
		out.push('--mb-sheet-h:calc(100dvh - ' + o.mtop + ')');
	return out.join(';') || null;
}

function described(o, id) {
	if (o.hint)
		return id + '-h';
	if (o.body)
		return id + '-d';
	return null;
}

function classes(o) {
	return [ 'mb-sheet', o.foot === 'row' ? 'mb-sheet-row' : '', o.compact ? 'mb-sheet-compact' : '', o.cls || '' ]
		.filter(Boolean).join(' ');
}

function closer(onClose) {
	var btn = E('button', { 'type': 'button', 'class': 'mb-btn mb-icon mb-sheet-x', 'aria-label': _('Close'), 'click': onClose });
	btn.innerHTML = CROSS;
	return btn;
}

return baseclass.extend({
	open: function(o) {
		var id = 'mb-sheet-' + (++seq);
		var back = trigger.back();
		var ovl, dialog, release, pop, pressed;

		function close() {
			if (!ovl.parentNode)
				return;
			ovl.parentNode.removeChild(ovl);
			var top = pop();
			release();
			var to = back && back.isConnected ? back : o.back && o.back();
			if (top && to && to.focus)
				to.focus();
			if (o.onClose)
				o.onClose();
		}

		function dismiss() {
			if (!(o.locked && o.locked()))
				close();
		}

		dialog = E('div', {
			'class': classes(o),
			'role': o.role || 'dialog',
			'aria-modal': 'true',
			'aria-labelledby': id,
			'aria-describedby': described(o, id),
			'tabindex': '-1',
			'style': vars(o)
		}, [
			E('div', { 'class': 'mb-sheet-grab' }),
			E('div', { 'class': 'mb-sheet-head' }, [
				o.icon || '',
				E('div', { 'class': 'mb-sheet-title' }, [
					E('h2', { 'id': id }, [ o.title ]),
					o.hint ? E('div', { 'class': 'mb-sheet-hint', 'id': id + '-h' }, [ o.hint ]) : ''
				]),
				o.closable === false ? '' : closer(dismiss)
			]),
			E('div', { 'class': 'mb-sheet-body', 'id': id + '-d' }, o.body ? [].concat(o.body) : []),
			E('div', { 'class': 'mb-sheet-foot' }, o.actions || [])
		]);

		ovl = E('div', { 'class': 'mb mb-ovl' }, [ dialog ]);
		ovl.addEventListener('pointerdown', function(ev) {
			pressed = ev.target === ovl;
			if (pressed)
				ev.preventDefault();
		});
		ovl.addEventListener('mousedown', function(ev) {
			if (ev.target === ovl)
				ev.preventDefault();
		});
		ovl.addEventListener('pointerup', function(ev) {
			pressed = pressed && ev.target === ovl;
		});
		ovl.addEventListener('click', function(ev) {
			var hit = ev.target === ovl && pressed;
			pressed = false;
			if (hit)
				dismiss();
		});
		release = scrolllock.lock();
		document.body.appendChild(ovl);
		pop = layers.push({
			node: ovl,
			dismiss: dismiss,
			tab: function(ev) {
				ev.preventDefault();
				focusable.cycle(dialog, ev.shiftKey);
			}
		});
		(dialog.querySelector('[data-autofocus]') || dialog).focus();

		return { node: dialog, close: close };
	}
});
