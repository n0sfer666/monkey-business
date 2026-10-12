'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.kit.inline as inline';
'require view.monkey-business.kit.switch as toggle';
'require view.monkey-business.model.interval as interval';

style.add(
  'subinterval',
  [
    '.mb .mb-sub-iv{field-sizing:content;min-width:0;padding:3px 8px}',
    '@supports not (field-sizing:content){.mb .mb-sub-iv{width:9ch}}',
    '.mb .mb-sub-iv.mb-sub-off{color:var(--mb-muted)}',
    '.mb .mb-sub-iv:focus{field-sizing:fixed;width:64px;padding:4px 8px;color:var(--mb-text);font-family:var(--mb-mono)}',
    '.mb .mb-sub-min{display:none}',
    '.mb .mb-sub-iv:focus~.mb-sub-min{display:inline}',
    '.mb .mb-sub-note{display:none;position:absolute;top:calc(100% + 6px);left:0;z-index:5;white-space:nowrap;',
    'padding:6px 9px;font-size:12px;background:var(--mb-pop);color:var(--mb-text-2);',
    'border:1px solid var(--mb-line-strong);border-radius:6px;box-shadow:0 6px 18px var(--mb-shadow)}',
    '.mb .mb-sub-note.mb-warn{color:var(--mb-warn-text);border-color:var(--mb-warn-edge)}',
    '.mb .mb-sub-iv:focus~.mb-sub-note{display:block}',
    '.mb .mb-sub-mob{display:none}',
    style.MOBILE + '{',
    '.mb .mb-sub-iv,.mb .mb-sub-min,.mb .mb-sub-note{display:none!important}',
    '.mb .mb-sub-mob{display:flex;flex-direction:column;gap:8px;padding:10px;background:var(--mb-bg);',
    'border:1px solid var(--mb-line);border-radius:8px}',
    '.mb .mb-sub-mobhead{display:flex;align-items:center;gap:10px}',
    '.mb .mb-sub-mobhead>span{flex:1;font-size:13px}',
    '.mb .mb-sub-mob:not(.mb-sub-off) .mb-sub-val{color:var(--mb-accent-text)}',
    '.mb .mb-sub-mob input[type=range]{width:100%;height:16px;margin:4px 0 0;padding:0;border-radius:0;accent-color:var(--mb-accent);cursor:pointer}',
    '.mb .mb-sub-scale{display:flex;justify-content:space-between;color:var(--mb-faint);font-size:11px}',
    '.mb .mb-sub-mob.mb-sub-off input[type=range],.mb .mb-sub-mob.mb-sub-off .mb-sub-scale{display:none}',
    '}',
  ].join(''),
);

function desk(minutes, commit, readonly) {
  var note = E('div', { class: 'mb-sub-note', role: 'note' });
  var input = inline.render({
    value: String(minutes),
    mask: function (v) {
      return interval.text(v);
    },
    normalize: function (v) {
      return String(interval.clamp(v));
    },
    label: _('Auto-update interval in minutes, 0 turns it off'),
    size: 18,
    readonly: readonly,
    onCommit: function (v) {
      input.classList.toggle('mb-sub-off', v === '0');
      commit(+v);
    },
  });

  function hint() {
    var n = interval.note(input.value);

    note.textContent = n.text;
    note.classList.toggle('mb-warn', n.warn);
  }

  input.classList.add('mb-sub-iv');
  input.classList.toggle('mb-sub-off', minutes === 0);
  input.inputMode = 'numeric';
  input.addEventListener('focus', hint);
  input.addEventListener('input', function () {
    input.value = interval.digits(input.value);
    hint();
  });

  return [input, E('span', { class: 'mb-sub-min mb-muted' }, [_('min')]), note];
}

function mobile(id, minutes, commit, readonly) {
  var value = E('span', { class: 'mb-sub-val mb-muted' }, ['· ' + interval.text(minutes)]);
  var slider = E('input', {
    type: 'range',
    min: interval.MIN,
    max: interval.MAX,
    step: 5,
    value: minutes || interval.DEFAULT,
    'aria-label': _('Auto-update interval'),
    disabled: readonly ? '' : null,
  });
  var box;

  function set(n) {
    value.textContent = '· ' + interval.text(n);
    box.classList.toggle('mb-sub-off', n === 0);
    commit(n);
  }

  slider.addEventListener('input', function () {
    value.textContent = '· ' + interval.text(slider.value);
  });
  slider.addEventListener('change', function () {
    set(+slider.value);
  });
  box = E('div', { class: 'mb-sub-mob' + (minutes ? '' : ' mb-sub-off') }, [
    E('div', { class: 'mb-sub-mobhead' }, [
      E('span', { id: id }, [_('Auto-update') + ' ', value]),
      toggle.render({
        checked: minutes > 0,
        labelledby: id,
        disabled: readonly,
        onChange: function (on) {
          set(on ? +slider.value : 0);
        },
      }),
    ]),
    slider,
    E('div', { class: 'mb-sub-scale mb-mono' }, [
      E('span', {}, ['10 min']),
      E('span', {}, ['1 h']),
      E('span', {}, ['2 h']),
    ]),
  ]);

  return box;
}

return baseclass.extend({
  render: function (id, minutes, commit, readonly) {
    return desk(minutes, commit, readonly).concat(mobile(id, minutes, commit, readonly));
  },
});
