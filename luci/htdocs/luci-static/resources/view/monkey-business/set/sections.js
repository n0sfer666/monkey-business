'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.kit.field as field';
'require view.monkey-business.model.settings as schema';
'require view.monkey-business.model.datatype as datatype';
'require view.monkey-business.store as store';

style.add('set-sections', [
	'.mb .mb-set-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:14px;align-items:start}',
	'.mb .mb-set-head{padding:10px 14px}',
	'.mb .mb-set-head .mb-muted{margin-top:2px}',
	style.MOBILE + '{.mb .mb-set-grid{grid-template-columns:minmax(0,1fr)}.mb .mb-set-sec{border-radius:10px}}'
].join(''));

function current(s, r) {
	var v = store.get(s.sid, r.opt);
	return v == null ? r.def : v;
}

var CONTROLS = {
	flag: function(id, s, r, edit) {
		return field.check({ id: id, checked: current(s, r) === '1', onChange: function(on) { edit(on ? '1' : '0'); } });
	},
	select: function(id, s, r, edit) {
		return field.select({ id: id, value: current(s, r), options: r.options, onChange: edit });
	},
	text: function(id, s, r, edit) {
		return field.text({ id: id, value: current(s, r), mono: r.mono, placeholder: r.def, onInput: edit });
	}
};

function renderRow(s, r, errors, onChange) {
	var id = 'mb-' + s.sid + '-' + r.opt;
	var key = s.sid + '.' + r.opt;
	var row;

	function edit(raw) {
		var value = String(raw).trim();
		var msg = r.check ? datatype[r.check](value) : null;
		field.error(row, msg);
		delete errors[key];
		if (msg)
			errors[key] = msg;
		store.set(s.sid, r.opt, value);
		onChange();
	}

	row = field.row({
		id: id,
		label: r.label,
		hint: r.hint,
		layout: r.layout,
		width: r.width,
		control: CONTROLS[r.kind](id, s, r, edit)
	});
	return row;
}

function renderSection(s, errors, onChange) {
	return E('section', { 'class': 'mb-panel mb-set-sec' }, [
		E('div', { 'class': 'mb-set-head' }, [
			E('h2', {}, [ s.title ]),
			E('div', { 'class': 'mb-muted mb-small' }, [ s.hint ])
		])
	].concat(s.rows.map(function(r) { return renderRow(s, r, errors, onChange); })));
}

return baseclass.extend({
	render: function(errors, onChange) {
		return E('div', { 'class': 'mb-set-grid' }, schema.sections.map(function(s) {
			return renderSection(s, errors, onChange);
		}));
	}
});
