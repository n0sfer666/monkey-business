'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.kit.scrolllock as scrolllock';

style.add('menu', [
	'.mb.mb-menu{position:fixed;z-index:1001;width:220px;max-width:calc(100vw - 16px);padding:6px 0;background:var(--mb-menu);',
	'border:1px solid var(--mb-line-strong);border-radius:10px;box-shadow:0 12px 32px var(--mb-shadow)}',
	'.mb .mb-menu-item{display:flex;align-items:center;gap:12px;width:100%;min-height:44px;margin:0;padding:0 14px;background:none;',
	'border:0;border-radius:0;color:var(--mb-text);font:inherit;font-size:14px;text-align:left;cursor:pointer;box-shadow:none}',
	'.mb .mb-menu-item:hover,.mb .mb-menu-item:focus{background:var(--mb-btn-on);outline:none;box-shadow:none}',
	'.mb .mb-menu-item:focus-visible{outline:2px solid var(--mb-accent);outline-offset:-2px}',
	'.mb .mb-menu-ico{display:inline-flex;flex-shrink:0}',
	'.mb .mb-menu-ico svg{width:18px;height:18px}',
	'.mb .mb-menu-warn{color:var(--mb-warn-text)}',
	'.mb .mb-menu-danger{color:var(--mb-err-text)}',
	'.mb .mb-menu-sep{height:1px;margin:6px 0;background:var(--mb-line-strong)}'
].join(''));

var GAP = 8;
var current = null;

function place(menu, anchor) {
	var r = anchor.getBoundingClientRect();
	var w = menu.offsetWidth;
	var h = menu.offsetHeight;
	var left = Math.max(GAP, Math.min(r.right - w, window.innerWidth - w - GAP));
	var top = r.bottom + 4 + h > window.innerHeight - GAP ? Math.max(GAP, r.top - h - 4) : r.bottom + 4;
	menu.style.left = left + 'px';
	menu.style.top = top + 'px';
}

function label(it) {
	if (!it.icon)
		return [ it.label ];
	var ico = E('span', { 'class': 'mb-menu-ico' });
	ico.innerHTML = it.icon;
	return [ ico, E('span', {}, [ it.label ]) ];
}

function item(it, close) {
	return E('button', {
		'type': 'button',
		'role': 'menuitem',
		'tabindex': '-1',
		'class': 'mb-menu-item' + (it.kind ? ' mb-menu-' + it.kind : ''),
		'click': function() {
			close(true);
			it.run();
		}
	}, label(it));
}

function step(menu, dir) {
	var items = Array.prototype.slice.call(menu.querySelectorAll('.mb-menu-item'));
	var at = items.indexOf(document.activeElement);
	items[(at + dir + items.length) % items.length].focus();
}

return baseclass.extend({
	open: function(anchor, items) {
		var same = current && current.anchor === anchor;
		if (current)
			current.close(false);
		if (same)
			return;

		var menu = E('div', { 'class': 'mb mb-menu', 'role': 'menu' });
		var release;

		function outside(ev) {
			if (menu.contains(ev.target) || anchor.contains(ev.target))
				return;
			if (ev.type === 'touchstart')
				ev.preventDefault();
			close(false);
		}

		function gone() {
			close(false);
		}

		function moved() {
			if (anchor.getBoundingClientRect().top !== top)
				close(false);
		}

		function close(refocus) {
			if (!menu.parentNode)
				return;
			document.removeEventListener('mousedown', outside, true);
			document.removeEventListener('touchstart', outside, true);
			window.removeEventListener('resize', gone);
			window.removeEventListener('scroll', moved, true);
			release();
			menu.parentNode.removeChild(menu);
			anchor.setAttribute('aria-expanded', 'false');
			current = null;
			if (refocus)
				anchor.focus();
		}

		items.forEach(function(it) {
			menu.appendChild(it === '-' ? E('div', { 'class': 'mb-menu-sep', 'role': 'separator' }) : item(it, close));
		});
		menu.addEventListener('keydown', function(ev) {
			if (ev.key === 'ArrowDown' || ev.key === 'ArrowUp') {
				ev.preventDefault();
				return step(menu, ev.key === 'ArrowDown' ? 1 : -1);
			}
			if (ev.key === 'Escape' || ev.key === 'Tab') {
				ev.preventDefault();
				close(true);
			}
		});

		release = scrolllock.lock();
		document.body.appendChild(menu);
		place(menu, anchor);
		var top = anchor.getBoundingClientRect().top;
		anchor.setAttribute('aria-expanded', 'true');
		document.addEventListener('mousedown', outside, true);
		document.addEventListener('touchstart', outside, { capture: true, passive: false });
		window.addEventListener('resize', gone);
		window.addEventListener('scroll', moved, true);
		current = { anchor: anchor, close: close };
		menu.querySelector('.mb-menu-item').focus();
	},

	close: function() {
		if (current)
			current.close(true);
	}
});
