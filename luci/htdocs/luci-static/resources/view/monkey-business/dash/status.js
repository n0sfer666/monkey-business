'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.model.phase as phase';
'require view.monkey-business.dash.subselect as subselect';
'require view.monkey-business.dash.exitip as exitip';
'require view.monkey-business.dash.toggle as toggle';
'require view.monkey-business.dash.traffic as traffic';
'require view.monkey-business.dash.geoalert as geoalert';

style.add(
  'dash-status',
  [
    '.mb .mb-dash-status{display:flex;flex-direction:column;gap:12px;padding:14px 16px}',
    '.mb .mb-dash-strow{display:grid;grid-template-columns:minmax(0,1.3fr) minmax(0,1.2fr) minmax(0,1fr) auto;align-items:center;gap:20px}',
    '.mb .mb-dash-state{display:flex;align-items:center;gap:10px;min-width:0}',
    '.mb .mb-dash-state>div{display:flex;flex-direction:column;gap:2px;min-width:0}',
    '.mb .mb-dash-dot{flex-shrink:0;width:10px;height:10px;border-radius:50%;background:var(--mb-faint)}',
    '.mb .mb-dash-dot-ok{background:var(--mb-ok);box-shadow:0 0 0 4px var(--mb-ok-ring)}',
    '.mb .mb-dash-dot-warn{background:var(--mb-warn)}',
    '.mb .mb-dash-dot-err{background:var(--mb-err)}',
    '.mb .mb-dash-title{font-size:15px;font-weight:700}',
    '.mb .mb-dash-stale .mb-dash-state{opacity:.4}',
    style.MOBILE + '{',
    '.mb .mb-dash-status{padding:14px;border-radius:10px}',
    '.mb .mb-dash-strow{display:contents}',
    '.mb .mb-dash-title{font-size:16px}',
    '.mb .mb-dash-line{font-size:13px}',
    '.mb .mb-dash-status>.mb-dash-geoneed{order:1}',
    '.mb .mb-dash-status .mb-dash-toggle{order:2}',
    '}',
  ].join(''),
);

return baseclass.extend({
  render: function (st, o) {
    var dot = E('span', { 'aria-hidden': 'true' });
    var title = E('strong', { class: 'mb-dash-title' });
    var line = E('span', { class: 'mb-muted mb-dash-line' });
    var sub = subselect.render(st, o.readonly);
    var button = toggle.render({ readonly: o.readonly, onDone: o.onDone });
    var alert = geoalert.render(o.onGeo, o.readonly);
    var traf = traffic.render(st);
    var card = E('section', { class: 'mb-panel mb-dash-status', 'aria-label': _('Status') }, [
      E('div', { class: 'mb-dash-strow' }, [
        E('div', { class: 'mb-dash-state', 'aria-live': 'polite' }, [dot, E('div', {}, [title, line])]),
        sub.node,
        exitip.render(),
        button.node,
      ]),
      alert.node,
      traf.node,
    ]);

    return {
      node: card,
      update: function (cur, geo, text) {
        var info = phase.info(cur, text);

        dot.className = 'mb-dash-dot mb-dash-dot-' + info.dot;
        title.textContent = info.title;
        line.textContent = info.sub;
        line.title = cur.last_event || '';
        card.classList.remove('mb-dash-stale');
        sub.update(cur);
        button.update(cur, geoalert.missing(geo));
        alert.update(geo);
        traf.update(cur);
      },
      stale: function () {
        card.classList.add('mb-dash-stale');
      },
    };
  },
});
