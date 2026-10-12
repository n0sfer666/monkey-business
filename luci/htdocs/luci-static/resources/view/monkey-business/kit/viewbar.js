'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';

style.add(
  'viewbar',
  [
    '.mb.mb-view{display:flex;flex-direction:column;gap:14px;padding:4px 0 16px}',
    '.mb .mb-vbar{display:flex;align-items:center;gap:12px}',
    '.mb .mb-vbar-title{display:flex;align-items:center;gap:12px;flex:1;min-width:0}',
    '.mb .mb-vbar-sub{flex:1;min-width:0}',
    '.mb .mb-vbar-acts{display:flex;gap:12px}',
    style.MOBILE + '{',
    '.mb.mb-view{gap:12px;padding:0 11px}',
    '.mb .mb-vbar{display:contents}',
    '.mb .mb-vbar-title{flex-direction:column;align-items:flex-start;gap:2px}',
    '.mb .mb-vbar h1{font-size:18px}',
    '.mb .mb-vbar-sub{font-size:13px}',
    '.mb .mb-vbar-acts{order:2;position:sticky;bottom:0;z-index:2;gap:8px;margin:0 -16px;padding:12px 16px;',
    'background:var(--mb-bar);border-top:1px solid var(--mb-line)}',
    '.mb .mb-vbar-acts .mb-btn-primary{flex:1}',
    '}',
  ].join(''),
);

return baseclass.extend({
  render: function (title, sub, actions) {
    return E('div', { class: 'mb-vbar' }, [
      E('div', { class: 'mb-vbar-title' }, [E('h1', {}, [title]), E('span', { class: 'mb-vbar-sub mb-muted' }, [sub])]),
      E('div', { class: 'mb-vbar-acts' }, actions),
    ]);
  },
});
