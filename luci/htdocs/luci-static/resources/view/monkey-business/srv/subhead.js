'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.model.subs as model';

style.add(
  'subhead',
  [
    '.mb .mb-subs-head{display:flex;align-items:center;gap:12px;padding:10px 12px;border-bottom:1px solid var(--mb-line)}',
    '.mb .mb-subs-head .mb-muted{flex:1;min-width:0}',
    '.mb .mb-subs-add::after{content:attr(data-short);display:none}',
    style.MOBILE + '{',
    '.mb .mb-subs-head .mb-muted{display:none}',
    '.mb .mb-subs-head{gap:8px;border-bottom-color:var(--mb-line-soft)}',
    '.mb .mb-subs-shut .mb-subs-head{border-bottom:0}',
    '.mb .mb-subs-head h2{flex:1;min-width:0;font-size:15px}',
    '.mb .mb-subs-toggle{display:flex;align-items:center;gap:8px;width:100%;min-height:36px;margin:0;padding:0;',
    'background:none!important;border:0!important;border-radius:6px;box-shadow:none!important;color:inherit;',
    'font:inherit;font-size:15px!important;font-weight:600;line-height:normal;text-align:left;cursor:pointer}',
    '.mb .mb-subs-toggle:focus-visible{outline:2px solid var(--mb-accent);outline-offset:2px}',
    '.mb .mb-subs-chev{flex:none;display:block;width:16px;height:16px;color:var(--mb-muted);transition:transform .15s}',
    '.mb .mb-subs-toggle[aria-expanded="true"] .mb-subs-chev{transform:rotate(90deg)}',
    '.mb .mb-subs-label{display:flex;flex-direction:column;gap:2px;min-width:0}',
    '.mb .mb-subs-sum{overflow:hidden;color:var(--mb-muted);font-size:12px;font-weight:400;text-overflow:ellipsis;white-space:nowrap}',
    '.mb .mb-subs-add{padding:7px 12px;border-radius:6px;font-size:13px!important}',
    '.mb .mb-subs-long{display:none}',
    '.mb .mb-subs-add::after{display:inline}',
    '}',
  ].join(''),
);

var CHEVRON =
  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" ' +
  'stroke-linejoin="round" aria-hidden="true"><path d="M9 6l6 6-6 6"/></svg>';

function summary(list, active) {
  var on = list.find(function (s) {
    return s['.name'] === active;
  });

  if (!on) return '';

  return list.length > 1 ? model.title(on) + ' · ' + _('+%d reserve').format(list.length - 1) : model.title(on);
}

function toggle(o) {
  var chev = E('span', { class: 'mb-subs-chev' });

  chev.innerHTML = CHEVRON;

  return E(
    'button',
    { type: 'button', class: 'mb-subs-toggle', 'aria-expanded': o.open ? 'true' : 'false', click: o.onToggle },
    [
      chev,
      E('span', { class: 'mb-subs-label' }, [
        E('span', {}, [_('Subscriptions')]),
        o.open || !o.list.length ? '' : E('span', { class: 'mb-subs-sum' }, [summary(o.list, o.active)]),
      ]),
    ],
  );
}

return baseclass.extend({
  render: function (o) {
    return E('div', { class: 'mb-subs-head' }, [
      E('h2', {}, [o.narrow ? toggle(o) : _('Subscriptions')]),
      E('span', { class: 'mb-muted' }, [_('the active one is used first, the rest are a reserve')]),
      o.readonly
        ? ''
        : E(
            'button',
            {
              type: 'button',
              class: 'mb-btn mb-btn-sm mb-btn-tint mb-subs-add',
              'data-short': _('+ Add'),
              click: o.onAdd,
            },
            [E('span', { class: 'mb-subs-long' }, [_('+ Add subscription')])],
          ),
    ]);
  },
});
