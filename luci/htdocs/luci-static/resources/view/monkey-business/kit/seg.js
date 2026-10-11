'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';

style.add('seg', [
	'.mb .mb-seg{display:inline-flex;padding:2px;background:var(--mb-bg);border:1px solid var(--mb-line);border-radius:6px}',
	'.mb .mb-seg-opt{flex:1;margin:0;padding:4px 10px;background:transparent;color:var(--mb-muted);border:0;border-radius:4px;',
	'font:inherit;cursor:pointer;box-shadow:none;white-space:nowrap}',
	'.mb .mb-seg-opt:hover{color:var(--mb-text);box-shadow:none}',
	'.mb .mb-seg-opt[aria-checked="true"]{background:var(--mb-seg-on);color:var(--mb-text);box-shadow:inset 0 0 0 1px var(--mb-seg-ring)}',
	style.MOBILE + '{.mb .mb-seg{display:flex}.mb .mb-seg-opt{padding:8px 10px}}'
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

return baseclass.extend({
	render: function(o) {
		var group = E('div', { 'class': 'mb-seg', 'role': 'radiogroup', 'aria-label': o.label });

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
		return group;
	},

	relabel: function(scope, opts) {
		opts.forEach(function(opt) {
			var b = scope.querySelector('.mb-seg-opt[data-value="' + CSS.escape(opt.value) + '"]');
			if (b)
				b.textContent = opt.label;
		});
	}
});
