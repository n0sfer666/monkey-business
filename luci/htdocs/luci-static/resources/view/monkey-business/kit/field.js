'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';

style.add('field', [
	'.mb .mb-row{display:grid;grid-template-columns:minmax(0,1fr) auto;column-gap:12px;row-gap:2px;align-items:center;',
	'grid-template-areas:"label ctl" "hint ctl";padding:10px 14px;border-top:1px solid var(--mb-line-soft)}',
	'.mb .mb-row-bare{grid-template-areas:"label ctl"}',
	'.mb .mb-row-label{grid-area:label;min-width:0;line-height:16px}',
	'.mb .mb-row-ctl{grid-area:ctl;width:var(--mb-w,auto);display:flex;justify-content:flex-end}',
	'.mb .mb-row-hint{grid-area:hint;color:var(--mb-muted);font-size:12px}',
	'.mb .mb-hint-brief{display:none}',
	'.mb .mb-row-err{grid-column:1/-1;color:var(--mb-err-text);font-size:12px}',
	'.mb .mb-row-err:empty{display:none}',
	'.mb .mb-row-wide{grid-template-columns:minmax(0,1fr);grid-template-areas:"label" "ctl" "hint";row-gap:4px}',
	'.mb .mb-row-wide.mb-row-bare{grid-template-areas:"label" "ctl"}',
	'.mb .mb-row-wide .mb-row-ctl{width:100%}',
	style.MOBILE + '{',
	'.mb .mb-row{grid-template-areas:"label ctl" "hint hint";row-gap:6px}',
	'.mb .mb-row-bare{grid-template-areas:"label ctl"}',
	'.mb .mb-row-wide,.mb .mb-row-pick{grid-template-columns:minmax(0,1fr);grid-template-areas:"label" "ctl" "hint"}',
	'.mb .mb-row-pick.mb-row-bare{grid-template-areas:"label" "ctl"}',
	'.mb .mb-row-pick .mb-row-ctl{width:100%}',
	'.mb .mb-row-short .mb-row-ctl{width:96px}',
	'.mb .mb-row-label{line-height:17px}',
	'.mb .mb-hint-full{display:none}',
	'.mb .mb-hint-brief{display:inline}',
	'}'
].join(''));

function onValue(handler, prop) {
	return function(ev) { handler(ev.target[prop]); };
}

function withCurrent(options, value) {
	var known = options.some(function(opt) { return opt.value === value; });
	if (known || value == null || value === '')
		return options;
	return [ { value: value, label: value } ].concat(options);
}

function hintText(full, brief) {
	if (!brief)
		return [ full ];
	return [
		E('span', { 'class': 'mb-hint-full' }, [ full ]),
		E('span', { 'class': 'mb-hint-brief' }, [ brief ])
	];
}

return baseclass.extend({
	hint: hintText,

	text: function(o) {
		return E('input', {
			'id': o.id,
			'type': 'text',
			'class': 'mb-input' + (o.mono ? ' mb-mono' : ''),
			'value': o.value,
			'placeholder': o.placeholder,
			'spellcheck': 'false',
			'autocomplete': 'off',
			'input': onValue(o.onInput, 'value')
		});
	},

	select: function(o) {
		return E('select', { 'id': o.id, 'class': 'mb-input', 'change': onValue(o.onChange, 'value') },
			withCurrent(o.options, o.value).map(function(opt) {
				return E('option', { 'value': opt.value, 'selected': opt.value === o.value ? '' : null }, [ opt.label ]);
			}));
	},

	check: function(o) {
		return E('input', {
			'id': o.id,
			'type': 'checkbox',
			'class': 'mb-check',
			'checked': o.checked ? '' : null,
			'change': onValue(o.onChange, 'checked')
		});
	},

	row: function(o) {
		var described = (o.hint ? o.id + '-hint ' : '') + o.id + '-err';
		o.control.setAttribute('aria-describedby', described);
		return E('div', { 'class': 'mb-row' + (o.layout ? ' mb-row-' + o.layout : '') + (o.hint ? '' : ' mb-row-bare') }, [
			E('label', { 'class': 'mb-row-label', 'for': o.id }, [ o.label ]),
			E('div', { 'class': 'mb-row-ctl', 'style': o.width ? '--mb-w:' + o.width : null }, [ o.control ]),
			o.hint ? E('span', { 'class': 'mb-row-hint', 'id': o.id + '-hint' }, hintText(o.hint, o.brief)) : '',
			E('span', { 'class': 'mb-row-err', 'id': o.id + '-err', 'role': 'alert' })
		]);
	},

	error: function(row, msg) {
		var err = row.querySelector('.mb-row-err');
		var input = row.querySelector('.mb-input');
		err.textContent = msg || '';
		if (!input)
			return;
		input.classList.toggle('mb-bad', !!msg);
		input.setAttribute('aria-invalid', msg ? 'true' : 'false');
	}
});
