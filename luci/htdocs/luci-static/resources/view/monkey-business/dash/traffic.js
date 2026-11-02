'use strict';
'require baseclass';
'require dom';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.model.traffic as model';

style.add(
  'dash-traffic',
  [
    '.mb .mb-dash-traf{display:grid;grid-template-columns:auto minmax(0,1fr) auto auto auto;align-items:center;gap:12px;white-space:nowrap}',
    '.mb .mb-dash-traf-bar{height:6px;border-radius:3px;overflow:hidden;background:var(--mb-line)}',
    '.mb .mb-dash-traf-bar>div{height:100%;background:var(--mb-accent)}',
    '.mb .mb-dash-traf-u{display:flex;align-items:center;gap:12px;white-space:nowrap}',
    '.mb .mb-dash-traf-u>.mb-dash-grow{flex-grow:1}',
    '.mb .mb-dash-traf-s{display:flex;justify-content:flex-end}',
    style.MOBILE + '{',
    '.mb .mb-dash-traf{grid-template-columns:auto minmax(0,1fr) auto;grid-template-areas:"l u h" "b b b" "e e e";align-items:baseline;gap:6px 8px}',
    '.mb .mb-dash-traf>:nth-child(1){grid-area:l;font-size:12px}',
    '.mb .mb-dash-traf>:nth-child(2){grid-area:b}',
    '.mb .mb-dash-traf>:nth-child(3){grid-area:u;font-size:13px}',
    '.mb .mb-dash-traf>:nth-child(4){grid-area:e;font-size:12px}',
    '.mb .mb-dash-traf>:nth-child(5){grid-area:h;font-size:13px}',
    '.mb .mb-dash-traf-u{flex-wrap:wrap;gap:6px 8px}',
    '}',
  ].join(''),
);

var KEY = 'mb-dash-traffic-hidden';

function stored() {
  try {
    return window.localStorage.getItem(KEY) === '1';
  } catch (_) {
    return false;
  }
}

function store(on) {
  try {
    window.localStorage.setItem(KEY, on ? '1' : '0');
  } catch (_) {}
}

function muted(text) {
  return E('span', { class: 'mb-muted' }, [text]);
}

function expires(t) {
  return t.expire ? muted(_('expires %s').format(t.expire)) : E('span');
}

function toggle(wide, narrow, run) {
  return E('button', { type: 'button', class: 'mb-link', 'aria-label': wide, click: run }, [
    E('span', { class: 'mb-dash-wide' }, [wide]),
    E('span', { class: 'mb-dash-narrow' }, [narrow]),
  ]);
}

function limited(t, hide) {
  return E('div', { class: 'mb-dash-traf' }, [
    muted(_('Traffic')),
    E('div', { class: 'mb-dash-traf-bar' }, [E('div', { style: 'width:' + t.pct + '%' })]),
    E('span', { class: 'mb-mono' }, [t.used + ' / ' + t.total + ' GB']),
    expires(t),
    toggle(_('Hide traffic'), _('Hide'), hide),
  ]);
}

function unlimited(t) {
  return E('div', { class: 'mb-dash-traf-u' }, [
    muted(_('Traffic')),
    E('span', { class: 'mb-mono' }, [_('%s GB used').format(t.used)]),
    muted(_('no limit')),
    E('div', { class: 'mb-dash-grow' }),
    expires(t),
  ]);
}

function stub(show) {
  return E('div', { class: 'mb-dash-traf-s' }, [toggle(_('Show traffic'), _('Show traffic'), show)]);
}

return baseclass.extend({
  render: function (st) {
    var box = E('div', { class: 'mb-dash-traffic' });
    var hidden = stored();
    var cur = st;

    function flip(on) {
      return function () {
        hidden = on;
        store(on);
        draw();
        var btn = box.querySelector('button');

        if (btn) btn.focus();
      };
    }

    function draw() {
      var t = model.of(cur);

      box.hidden = t.kind === 'none';
      if (t.kind === 'unlimited') return dom.content(box, unlimited(t));
      if (t.kind === 'limited') return dom.content(box, hidden ? stub(flip(false)) : limited(t, flip(true)));
      dom.content(box, '');
    }

    draw();

    return {
      node: box,
      update: function (next) {
        var was = JSON.stringify(model.of(cur));

        cur = next;
        if (JSON.stringify(model.of(cur)) !== was) draw();
      },
    };
  },
});
