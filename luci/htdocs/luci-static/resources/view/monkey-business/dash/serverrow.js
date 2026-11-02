'use strict';
'require baseclass';
'require view.monkey-business.availability as availability';
'require dom';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.kit.icons as icons';
'require view.monkey-business.model.servers as model';
'require view.monkey-business.srv.pingbar as pingbar';

style.add(
  'dash-srvrow',
  [
    '.mb .mb-dash-srow,.mb .mb-dash-shead{display:grid;grid-template-columns:36px minmax(0,1fr) 150px 170px 64px;gap:10px;align-items:center}',
    '.mb .mb-dash-shead{padding:7px 12px;color:var(--mb-muted);font-size:12px;border-bottom:1px solid var(--mb-line)}',
    '.mb .mb-dash-srow{padding:4px 12px;min-height:45px;border-bottom:1px solid var(--mb-line-soft)}',
    '.mb .mb-dash-srow.mb-on{background:var(--mb-row-on)}',
    '.mb .mb-dash-srow.mb-cut{color:var(--mb-dim)}',
    '.mb .mb-dash-prio{color:var(--mb-muted);font-family:var(--mb-mono)}',
    '.mb .mb-dash-sname{display:flex;flex-direction:column;gap:2px;min-width:0}',
    '.mb .mb-dash-sname>div{display:flex;align-items:center;gap:8px;min-width:0}',
    '.mb .mb-dash-sname>div>span:first-child{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}',
    '.mb .mb-dash-badge{flex-shrink:0;padding:1px 6px;border-radius:4px;background:var(--mb-ok-tint);color:var(--mb-ok-text);font-size:11px}',
    '.mb .mb-dash-srow .mb-ping-bar{width:70px}',
    '.mb .mb-dash-sacts{display:flex;gap:4px;justify-content:flex-end}',
    '.mb .mb-dash-sacts .mb-icon{border-radius:5px}',
    style.MOBILE + '{',
    '.mb .mb-dash-shead{display:none}',
    '.mb .mb-dash-srow{grid-template-columns:18px minmax(0,1fr) auto 36px;padding:7px 12px;min-height:0;border-bottom:0;border-top:1px solid var(--mb-line-soft)}',
    '.mb .mb-dash-prio{font-size:12px}',
    '.mb .mb-dash-sname>div{gap:6px}',
    '.mb .mb-dash-badge{padding:0 6px}',
    '.mb .mb-dash-sproto{display:none}',
    '.mb .mb-dash-sname .mb-dash-narrow{font-size:12px}',
    '.mb .mb-dash-sping{display:none}',
    '.mb .mb-dash-sacts .mb-icon{border-radius:6px}',
    '}',
  ].join(''),
);

function iconButton(label, svg, run, extra) {
  var btn = E('button', {
    type: 'button',
    class: 'mb-btn mb-icon' + (extra.cls || ''),
    'aria-label': label,
    title: label,
    click: run,
  });

  btn.innerHTML = svg;
  if (extra.disabled) btn.setAttribute('aria-disabled', 'true');

  return btn;
}

function rowClass(s, active) {
  var cut = s.disabled || s.auto_disabled;

  return 'mb-dash-srow' + (active ? ' mb-on' : '') + (cut ? ' mb-cut' : '');
}

function connectLabel(s) {
  return s.disabled ? _('Server is off — turn it on on the Servers tab') : _('Connect');
}

return baseclass.extend({
  head: function () {
    return E('div', { class: 'mb-dash-shead', 'aria-hidden': 'true' }, [
      E('span', {}, ['#']),
      E('span', {}, [_('Name')]),
      E('span', {}, [_('Protocol')]),
      E('span', {}, [_('Ping')]),
      E('span'),
    ]);
  },

  render: function (s, at, o) {
    var proto = model.protocol(s);
    var cell = E('div');
    var row = E('div', { class: rowClass(s, o.active), 'data-id': availability.key(availability.ref(s)) }, [
      E('span', { class: 'mb-dash-prio' }, [String(at + 1)]),
      E('div', { class: 'mb-dash-sname' }, [
        E('div', {}, [
          E('span', { title: s.tag }, [s.tag]),
          o.active ? E('span', { class: 'mb-dash-badge' }, [_('active')]) : '',
        ]),
        E('span', { class: 'mb-muted mb-dash-narrow' }, [proto]),
      ]),
      E('span', { class: 'mb-muted mb-dash-sproto' }, [proto]),
      cell,
      E('div', { class: 'mb-dash-sacts' }, [
        iconButton(
          _('Ping'),
          icons.PULSE,
          function () {
            o.onPing(s);
          },
          { cls: ' mb-dash-sping', disabled: o.pinging },
        ),
        iconButton(
          connectLabel(s),
          icons.ARROW,
          function () {
            o.onConnect(s);
          },
          { cls: ' mb-dash-sgo', disabled: s.disabled || o.locked },
        ),
      ]),
    ]);

    function paint(r) {
      dom.content(cell, pingbar.render(model.ping(model.pingOf(r))));
    }

    paint(s);

    return { node: row, ping: paint };
  },
});
