'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';

style.add('sheet', [
	'.mb.mb-ovl{position:fixed;inset:0;z-index:1000;display:flex;align-items:center;justify-content:center;padding:16px;',
	'background:var(--mb-overlay)}',
	'.mb .mb-sheet{display:flex;flex-direction:column;width:var(--mb-sheet-w,540px);max-width:100%;max-height:calc(100vh - 32px);',
	'background:var(--mb-panel);border:1px solid var(--mb-line-strong);border-radius:10px;box-shadow:0 18px 50px var(--mb-shadow)}',
	'.mb .mb-sheet-grab{display:none;width:40px;height:4px;margin:8px auto 0;border-radius:2px;background:var(--mb-line-strong)}',
	'.mb .mb-sheet-head{display:flex;align-items:flex-start;gap:12px;padding:14px 16px 10px}',
	'.mb .mb-sheet-title{flex:1;min-width:0}',
	'.mb .mb-sheet-title h2{font-size:15px}',
	'.mb .mb-sheet-body{padding:0 16px 14px;overflow:auto}',
	'.mb .mb-sheet-foot{display:flex;justify-content:flex-end;gap:8px;padding:12px 16px;border-top:1px solid var(--mb-line-soft)}',
	'.mb .mb-sheet-foot:empty{display:none}',
	style.MOBILE + '{',
	'.mb.mb-ovl{align-items:flex-end;padding:0}',
	'.mb .mb-sheet{width:100%;max-height:92vh;border-radius:16px 16px 0 0;border-bottom:0}',
	'.mb .mb-sheet-grab{display:block}',
	'.mb .mb-sheet-foot{flex-direction:column-reverse;padding:12px 16px 16px}',
	'.mb .mb-sheet-foot .mb-btn{width:100%;padding:12px}',
	'}'
].join(''));

var CROSS = '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">' +
	'<path d="M6 6l12 12M18 6L6 18"></path></svg>';

var seq = 0;
var FOCUSABLE = 'button:not([disabled]),input:not([disabled]),select:not([disabled]),textarea:not([disabled]),' +
	'a[href],[tabindex]:not([tabindex="-1"])';

function closer(onClose) {
	var btn = E('button', { 'type': 'button', 'class': 'mb-btn mb-icon', 'aria-label': _('Close'), 'click': onClose });
	btn.innerHTML = CROSS;
	return btn;
}

function silence(ovl) {
	return Array.prototype.filter.call(document.body.children, function(el) {
		return el !== ovl && !el.inert;
	}).map(function(el) {
		el.inert = true;
		return el;
	});
}

function trap(dialog, ev) {
	var items = dialog.querySelectorAll(FOCUSABLE);
	if (!items.length)
		return ev.preventDefault();
	var at = document.activeElement;
	var edge = ev.shiftKey ? items[0] : items[items.length - 1];
	if (at !== edge && at !== dialog && dialog.contains(at))
		return;
	ev.preventDefault();
	(ev.shiftKey ? items[items.length - 1] : items[0]).focus();
}

return baseclass.extend({
	open: function(o) {
		var id = 'mb-sheet-' + (++seq);
		var back = document.activeElement;
		var muted = [];
		var ovl, dialog;

		function close() {
			if (!ovl.parentNode)
				return;
			muted.forEach(function(el) { el.inert = false; });
			ovl.parentNode.removeChild(ovl);
			var to = back && back.isConnected ? back : o.back && o.back();
			if (to && to.focus)
				to.focus();
			if (o.onClose)
				o.onClose();
		}

		function dismiss() {
			if (!(o.locked && o.locked()))
				close();
		}

		dialog = E('div', {
			'class': 'mb-sheet',
			'role': o.role || 'dialog',
			'aria-modal': 'true',
			'aria-labelledby': id,
			'aria-describedby': o.body ? id + '-d' : null,
			'tabindex': '-1',
			'style': o.width ? '--mb-sheet-w:' + o.width : null
		}, [
			E('div', { 'class': 'mb-sheet-grab' }),
			E('div', { 'class': 'mb-sheet-head' }, [
				o.icon || '',
				E('div', { 'class': 'mb-sheet-title' }, [
					E('h2', { 'id': id }, [ o.title ]),
					o.hint ? E('div', { 'class': 'mb-muted mb-small' }, [ o.hint ]) : ''
				]),
				o.closable === false ? '' : closer(dismiss)
			]),
			E('div', { 'class': 'mb-sheet-body', 'id': id + '-d' }, o.body ? [ o.body ] : []),
			E('div', { 'class': 'mb-sheet-foot' }, o.actions || [])
		]);

		ovl = E('div', { 'class': 'mb mb-ovl' }, [ dialog ]);
		ovl.addEventListener('mousedown', function(ev) {
			if (ev.target === ovl)
				dismiss();
		});
		ovl.addEventListener('keydown', function(ev) {
			if (ev.key === 'Tab')
				return trap(dialog, ev);
			if (ev.key !== 'Escape')
				return;
			ev.stopPropagation();
			dismiss();
		});
		document.body.appendChild(ovl);
		muted = silence(ovl);
		(dialog.querySelector('[data-autofocus]') || dialog).focus();

		return { node: dialog, close: close };
	}
});
