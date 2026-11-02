'use strict';
'require baseclass';

function inGroup(s, by) {
  return by === 'manual' ? s.sub == null : s.sub === by;
}

function label(sub, active) {
  if (sub.id === active) return { text: _('Active · %s').format(sub.name), node: _('Active · %s').format(sub.name) };

  return {
    text: _('Reserve · %s').format(sub.name),
    node: E('span', {}, [E('span', { class: 'mb-dash-wide' }, [_('Reserve · ')]), sub.name]),
  };
}

function of(servers, st) {
  var active = st.active_sub;
  var subs = (st.subscriptions || []).slice().sort(function (a, b) {
    return (b.id === active) - (a.id === active);
  });
  var out = [];

  subs.forEach(function (sub) {
    if (
      sub.id !== active &&
      !servers.some(function (s) {
        return inGroup(s, sub.id);
      })
    )
      return;
    var l = label(sub, active);

    out.push({ value: sub.id, label: l.node, text: l.text });
  });
  if (
    servers.some(function (s) {
      return s.sub == null;
    })
  )
    out.push({ value: 'manual', label: _('Manual'), text: _('Manual') });

  return out;
}

function pick(groups, cur, active) {
  var has = function (v) {
    return groups.some(function (g) {
      return g.value === v;
    });
  };

  if (cur != null && has(cur)) return cur;
  if (has(active)) return active;

  return groups.length ? groups[0].value : null;
}

return baseclass.extend({
  inGroup: inGroup,
  of: of,
  pick: pick,
});
