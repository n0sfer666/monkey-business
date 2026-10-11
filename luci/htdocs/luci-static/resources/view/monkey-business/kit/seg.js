'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.kit.overflow as overflow';

style.add('seg', [
	'.mb .mb-seg{display:inline-flex;max-width:100%;padding:2px;background:var(--mb-bg);border:1px solid var(--mb-line);border-radius:6px}',
	'.mb .mb-seg-opt{flex:1 0 auto;display:inline-flex;align-items:center;justify-content:center;',
	'margin:0;padding:6px 14px;background:transparent;color:var(--mb-muted);border:0;border-radius:4px;',
	'font:inherit;font-size:14px;font-weight:500;line-height:normal;text-decoration:none;cursor:pointer;box-shadow:none;white-space:nowrap}',
	'.mb .mb-seg-opt:hover,.mb .mb-seg-opt:focus{text-decoration:none;box-shadow:none}.mb .mb-seg-opt:hover{color:var(--mb-text)}',
	'.mb .mb-seg-opt[aria-checked="true"],.mb .mb-seg-opt[aria-current="page"]{background:var(--mb-seg-on);color:var(--mb-text);',
	'box-shadow:inset 0 0 0 1px var(--mb-seg-ring)}',
	'.mb .mb-seg-opt:focus-visible{outline:2px solid var(--mb-accent);outline-offset:-2px}',
	'.mb .mb-seg-compact{position:relative;overflow-x:auto;scrollbar-width:none;overscroll-behavior-x:contain}',
	'.mb .mb-seg-compact::-webkit-scrollbar{display:none}',
	'.mb .mb-seg-compact>.mb-seg-opt{padding:4px 10px;font-size:inherit}',
	style.MOBILE + '{.mb .mb-seg{display:flex}.mb .mb-seg>.mb-seg-opt{min-height:36px;padding:0 12px}.mb .mb-seg-compact>.mb-seg-opt{min-height:32px}}'
].join(''));

function options(group) {
	return Array.prototype.slice.call(group.querySelectorAll('.mb-seg-opt'));
}

function select(group, value) {
	var opts = options(group);
	opts.forEach(function(b) {
		var on = b.getAttribute('data-value') === value;
		b.setAttribute('aria-checked', on ? 'true' : 'false');
		b.tabIndex = on ? 0 : -1;
	});
	if (!group.querySelector('[aria-checked="true"]') && opts.length)
		opts[0].tabIndex = 0;
}

function step(group, dir) {
	var opts = options(group);
	var cur = opts.findIndex(function(b) { return b.getAttribute('aria-checked') === 'true'; });
	if (cur < 0)
		cur = dir > 0 ? -1 : 0;
	return opts[(cur + dir + opts.length) % opts.length];
}

var KEYS = { 'ArrowRight': 1, 'ArrowDown': 1, 'ArrowLeft': -1, 'ArrowUp': -1 };

function links(o, cls) {
	return E('nav', { 'class': cls, 'aria-label': o.label }, o.options.map(function(opt) {
		return E('a', {
			'class': 'mb-seg-opt',
			'href': opt.href,
			'data-value': opt.value,
			'aria-current': opt.value === o.value ? 'page' : null
		}, [ opt.label ]);
	}));
}

function radios(o, cls) {
	var group = E('div', { 'class': cls, 'role': 'radiogroup', 'aria-label': o.label });

	function pick(value) {
		select(group, value);
		o.onChange(value);
	}

	o.options.forEach(function(opt) {
		group.appendChild(E('button', {
			'type': 'button',
			'class': 'mb-seg-opt',
			'role': 'radio',
			'data-value': opt.value,
			'click': function() { pick(opt.value); }
		}, [ opt.label ]));
	});

	group.addEventListener('keydown', function(ev) {
		if (!KEYS[ev.key])
			return;
		ev.preventDefault();
		var next = step(group, KEYS[ev.key]);
		next.focus();
		pick(next.getAttribute('data-value'));
	});

	select(group, o.value);
	return o.compact ? overflow.wrap(group, function() { return group.querySelector('[aria-checked="true"]'); }) : group;
}

return baseclass.extend({
	render: function(o) {
		var cls = 'mb-seg' + (o.compact ? ' mb-seg-compact' : '');
		return o.onChange ? radios(o, cls) : links(o, cls);
	},

	relabel: function(scope, opts) {
		opts.forEach(function(opt) {
			var b = scope.querySelector('.mb-seg-opt[data-value="' + CSS.escape(opt.value) + '"]');
			if (b)
				b.textContent = opt.label;
		});
	}
});
