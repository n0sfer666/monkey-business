'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';

style.add('tip', [
	'.mb .mb-tip{position:relative;display:inline-flex;align-items:center;gap:4px;color:var(--mb-muted);cursor:help;outline:none}',
	'.mb .mb-tip:focus-visible{outline:2px solid var(--mb-accent);outline-offset:2px;border-radius:3px}',
	'.mb .mb-tip-b{display:none;position:absolute;bottom:calc(100% + 8px);right:-6px;z-index:5;width:max-content;max-width:260px;',
	'background:var(--mb-pop);color:var(--mb-text);border:1px solid var(--mb-line-strong);border-radius:6px;padding:6px 9px;',
	'font-size:12px;font-weight:400;line-height:1.35;white-space:normal;box-shadow:0 6px 18px var(--mb-shadow)}',
	'.mb .mb-tip:hover .mb-tip-b,.mb .mb-tip:focus .mb-tip-b,.mb .mb-tip.mb-open .mb-tip-b{display:block}'
].join(''));

var ICON = '<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">' +
	'<circle cx="12" cy="12" r="9"></circle><path d="M12 11v5M12 8v.5"></path></svg>';

function make(role, text, svg, before, after) {
	var icon = E('span', { 'style': 'display:inline-flex' });
	var tip = E('span', { 'class': 'mb-tip', 'tabindex': '0', 'role': role, 'aria-label': text }, [
		before || '',
		icon,
		after || '',
		E('span', { 'class': 'mb-tip-b', 'aria-hidden': 'true' }, [ text ])
	]);

	function open(on) {
		tip.classList.toggle('mb-open', on);
		if (role === 'button')
			tip.setAttribute('aria-expanded', on ? 'true' : 'false');
	}

	icon.innerHTML = svg;
	open(false);
	tip.addEventListener('click', function() { open(!tip.classList.contains('mb-open')); });
	tip.addEventListener('keydown', function(ev) {
		if (ev.key !== 'Enter' && ev.key !== ' ')
			return;
		ev.preventDefault();
		open(!tip.classList.contains('mb-open'));
	});
	tip.addEventListener('blur', function() { open(false); });
	return tip;
}

return baseclass.extend({
	render: function(text, label) {
		return make('note', text, ICON, label);
	},

	icon: function(text, svg) {
		return make('button', text, svg, '');
	}
});
