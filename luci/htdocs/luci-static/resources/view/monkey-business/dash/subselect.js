'use strict';
'require baseclass';
'require view.monkey-business.api as api';
'require view.monkey-business.subs as subs';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.kit.notify as notice';

style.add(
  'dash-sub',
  [
    '.mb .mb-dash-field{display:flex;flex-direction:column;gap:4px;min-width:0}',
    '.mb .mb-dash-subrow{display:flex;align-items:center;gap:8px;min-width:0}',
    '.mb select.mb-input.mb-dash-sub{width:auto;min-width:170px;max-width:100%;padding-left:10px;padding-right:32px}',
    '.mb .mb-dash-auto{color:var(--mb-warn-text)}',
    style.STACK +
      '{.mb .mb-dash-subrow>.mb-dash-wide{display:none}.mb .mb-dash-subf>label>.mb-dash-narrow{display:inline}}',
    style.MOBILE + '{.mb select.mb-input.mb-dash-sub{width:100%;min-width:0;padding-right:34px}}',
  ].join(''),
);

function reasonText(reason) {
  if (reason === 'exhausted') return _('ran out of traffic');

  return reason === 'expired' ? _('expired') : reason;
}

function optionLabel(sub) {
  return sub.alive ? sub.name : sub.name + ' — ' + _('expired or out of traffic');
}

function reserveText(list) {
  return list.length > 1 ? _('+%d reserve').format(list.length - 1) : '';
}

function autoText(st) {
  var a = st.autoswitch;

  return a ? _('Switched automatically: %s %s.').format(subs.name(st.subscriptions, a.from), reasonText(a.reason)) : '';
}

function fill(select, list) {
  select.textContent = '';
  list.forEach(function (sub) {
    select.appendChild(E('option', { value: sub.id }, [optionLabel(sub)]));
  });
}

function switchTo(select, back) {
  select.disabled = true;

  return api
    .subscriptionSelect(select.value)
    .then(function (res) {
      if (!(res && res.error)) return window.location.reload();
      select.value = back;
      notice.show(_('Subscription not switched: ') + res.error, 'warning');
    })
    .catch(function (e) {
      select.value = back;
      notice.show(
        _('No answer yet, the switch may still be applying; the status refreshes on its own: ') + e,
        'warning',
      );
    });
}

return baseclass.extend({
  render: function (st, readonly) {
    var active = st.active_sub;
    var shown = null;
    var select = E('select', { id: 'mb-dash-sub', class: 'mb-input mb-dash-sub', disabled: readonly ? '' : null });
    var wide = E('span', { class: 'mb-muted mb-dash-wide' });
    var narrow = E('span', { class: 'mb-dash-narrow' });
    var auto = E('span', { class: 'mb-small mb-dash-auto' });
    var box = E('div', { class: 'mb-dash-field mb-dash-subf' }, [
      E('label', { class: 'mb-muted mb-small', for: 'mb-dash-sub' }, [_('Subscription'), narrow]),
      E('div', { class: 'mb-dash-subrow' }, [select, wide]),
      auto,
    ]);

    var switching = false;

    select.addEventListener('change', function () {
      switching = true;
      switchTo(select, active).finally(function () {
        switching = false;
        select.disabled = !!readonly;
      });
    });

    function update(cur) {
      var list = cur.subscriptions || [];
      var ids = list
        .map(function (sub) {
          return sub.id;
        })
        .join(' ');
      var focused = document.activeElement === select;

      active = cur.active_sub;
      box.hidden = list.length === 0;
      if (!focused && ids !== shown) {
        fill(select, list);
        shown = ids;
      }
      if (!focused && !switching) select.value = active;
      wide.textContent = reserveText(list);
      narrow.textContent = list.length > 1 ? ' · ' + reserveText(list) : '';
      auto.textContent = autoText(cur);
      auto.hidden = !cur.autoswitch;
    }

    update(st);

    return { node: box, update: update };
  },
});
