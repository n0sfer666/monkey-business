'use strict';
'require baseclass';
'require view.monkey-business.dash.ruleedit as ruleedit';

function lists() {
  return [
    {
      key: 'direct',
      title: _('Direct'),
      sub: _('bypass VPN'),
      hint: _('Bypass the VPN, go straight through the ISP'),
      placeholder: 'example.com\n*.example.org\n10.0.0.0/8\ngeosite:category-ru',
    },
    {
      key: 'proxy',
      title: _('Via VPN'),
      sub: _('always tunnelled'),
      hint: _('Always tunnelled, even if the region is local'),
      placeholder: 'blocked.example\n*.example.net\ngeosite:google\ngeoip:telegram',
    },
  ];
}

function hint() {
  var kinds = ['domain', '*.domain', 'IP/CIDR', 'geosite:NAME', 'geoip:NAME'];
  var out = [_('One entry per line:') + ' '];

  kinds.forEach(function (k, i) {
    out.push(E('code', {}, [k]));
    if (i < kinds.length - 1) out.push(', ');
  });

  return E('span', { class: 'mb-cr-hint' }, out);
}

function column(d, value, onPick) {
  d.ed = ruleedit.render({ id: 'mb-cr-' + d.key, label: d.title, value: value, placeholder: d.placeholder });
  d.count = E('span', { class: 'mb-cr-count' });
  d.tcount = E('span', { class: 'mb-cr-count' });
  d.tab = E(
    'button',
    {
      type: 'button',
      class: 'mb-btn mb-cr-tab',
      role: 'tab',
      id: 'mb-cr-tab-' + d.key,
      'aria-controls': 'mb-cr-col-' + d.key,
      click: function () {
        onPick(d.key);
      },
    },
    [E('span', { class: 'mb-cr-dot mb-cr-dot-' + d.key }), ' ' + d.title + ' ', d.tcount],
  );

  return E(
    'div',
    {
      class: 'mb-cr-col',
      id: 'mb-cr-col-' + d.key,
      'data-list': d.key,
      role: 'tabpanel',
      'aria-labelledby': 'mb-cr-tab-' + d.key,
    },
    [
      E('div', { class: 'mb-cr-chead' }, [
        E('span', { class: 'mb-cr-dot mb-cr-dot-' + d.key }),
        E('label', { for: 'mb-cr-' + d.key }, [d.title]),
        E('span', { class: 'mb-cr-sub' }, [d.sub]),
        d.count,
      ]),
      d.ed.node,
    ],
  );
}

return baseclass.extend({
  column: column,
  lists: lists,
  hint: hint,
});
