'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';

style.add('inline', [
	'.mb .mb-inl{display:inline-block;width:auto;min-width:4ch;max-width:100%;height:auto;margin:0;padding:3px 7px;',
	'background:transparent;color:inherit;border:1px dashed var(--mb-line-strong);border-radius:5px;',
	'font:inherit;line-height:normal;box-shadow:none}',
	'.mb .mb-inl.mb-mono{font-family:var(--mb-mono)}',
	'.mb .mb-inl:hover{border-color:var(--mb-muted)!important}',
	'.mb .mb-inl:focus{outline:none;background:var(--mb-bg);border-style:solid;border-color:var(--mb-accent)!important;box-shadow:none}',
	'.mb .mb-inl.mb-bad{border-color:var(--mb-err)!important}'
].join(''));

function shown(o, value) {
	if (o.mask && value)
		return o.mask(value);
	return value;
}

return baseclass.extend({
	render: function(o) {
		var saved = o.value || '';
		var input = E('input', {
			'type': 'text',
			'readonly': o.readonly ? '' : null,
			'class': 'mb-inl' + (o.mono ? ' mb-mono' : ''),
			'value': shown(o, saved),
			'placeholder': o.placeholder,
			'aria-label': o.label,
			'spellcheck': 'false',
			'autocomplete': 'off',
			'size': Math.max(4, Math.min(o.size || 24, Math.max(saved.length, shown(o, saved).length, (o.placeholder || '').length) + 1))
		});

		function commit() {
			if (o.readonly)
				return null;
			var next = o.normalize ? o.normalize(input.value.trim()) : input.value.trim();
			var bad = o.validate ? o.validate(next) : null;
			input.classList.toggle('mb-bad', !!bad);
			input.title = bad || '';
			if (bad || next === saved)
				return bad;
			saved = next;
			o.onCommit(next);
			return null;
		}

		input.addEventListener('focus', function() {
			if (!input.classList.contains('mb-bad'))
				input.value = saved;
			input.select();
		});
		input.addEventListener('blur', function() {
			if (!commit())
				input.value = shown(o, saved);
		});
		input.addEventListener('keydown', function(ev) {
			if (ev.key === 'Enter')
				input.blur();
			if (ev.key !== 'Escape')
				return;
			input.value = saved;
			input.classList.remove('mb-bad');
			input.blur();
		});
		return input;
	}
});
