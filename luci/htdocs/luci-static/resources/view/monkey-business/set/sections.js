'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.kit.field as field';
'require view.monkey-business.model.settings as schema';
'require view.monkey-business.model.datatype as datatype';
'require view.monkey-business.store as store';

style.add(
  'set-sections',
  [
    '.mb .mb-set-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:14px;align-items:start}',
    '.mb .mb-set-head{padding:10px 14px;border-bottom:1px solid var(--mb-line)}',
    '.mb .mb-set-sec .mb-row{border-top:0;border-bottom:1px solid var(--mb-line-soft)}',
    '.mb .mb-set-sec .mb-row:last-child{border-bottom:0}',
    '.mb .mb-set-grid .mb-input{line-height:normal}',
    '.mb .mb-set-grid select.mb-input{padding-left:10px;padding-right:32px;background-position:right 10px center}',
    style.MOBILE + '{',
    '.mb .mb-set-grid{grid-template-columns:minmax(0,1fr);gap:12px}',
    '.mb .mb-set-sec{border-radius:10px}',
    '.mb .mb-set-head{display:flex;flex-direction:column;gap:2px;border-bottom:0}',
    '.mb .mb-set-head h2{font-size:15px}',
    '.mb .mb-set-sec .mb-row,.mb .mb-set-sec .mb-row:last-child{border-top:1px solid var(--mb-line-soft);border-bottom:0}',
    '.mb .mb-set-grid .mb-input{border-radius:6px}',
    '.mb .mb-set-grid .mb-row-short .mb-input{padding:7px 8px}',
    '.mb .mb-set-grid select.mb-input{padding-right:34px;background-position:right 12px center}',
    '}',
  ].join(''),
);

function current(s, r) {
  var v = store.get(s.sid, r.opt);

  return v == null ? r.def : v;
}

var CONTROLS = {
  flag: function (id, s, r, edit, ro) {
    return field.check({
      id: id,
      checked: current(s, r) === '1',
      disabled: ro,
      onChange: function (on) {
        edit(on ? '1' : '0');
      },
    });
  },
  select: function (id, s, r, edit, ro) {
    return field.select({ id: id, value: current(s, r), options: r.options, disabled: ro, onChange: edit });
  },
  text: function (id, s, r, edit, ro) {
    return field.text({ id: id, value: current(s, r), mono: r.mono, placeholder: r.def, disabled: ro, onInput: edit });
  },
};

function renderRow(s, r, errors, onChange, ro) {
  var id = 'mb-' + s.sid + '-' + r.opt;
  var key = s.sid + '.' + r.opt;
  var row;

  function edit(raw) {
    var value = String(raw).trim();
    var msg = r.check ? datatype[r.check](value) : null;

    field.error(row, msg);
    delete errors[key];
    if (msg) errors[key] = msg;
    store.set(s.sid, r.opt, value);
    onChange();
  }

  row = field.row({
    id: id,
    label: r.label,
    hint: r.hint,
    brief: r.brief,
    layout: r.layout,
    width: r.width,
    control: CONTROLS[r.kind](id, s, r, edit, ro),
  });

  return row;
}

function renderSection(s, errors, onChange, ro) {
  return E(
    'section',
    { class: 'mb-panel mb-set-sec' },
    [
      E('div', { class: 'mb-set-head' }, [
        E('h2', {}, [s.title]),
        E('span', { class: 'mb-muted mb-small' }, field.hint(s.hint, s.brief)),
      ]),
    ].concat(
      s.rows.map(function (r) {
        return renderRow(s, r, errors, onChange, ro);
      }),
    ),
  );
}

return baseclass.extend({
  render: function (errors, onChange, ro) {
    return E(
      'div',
      { class: 'mb-set-grid' },
      schema.sections.map(function (s) {
        return renderSection(s, errors, onChange, ro);
      }),
    );
  },
});
