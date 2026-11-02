'use strict';
'require baseclass';
'require view.monkey-business.model.requestid as requestid';
'require dom';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.api as api';
'require view.monkey-business.kit.sheet as sheet';
'require view.monkey-business.kit.notify as notice';
'require view.monkey-business.kit.icons as icons';

style.add(
  'corporate',
  [
    '.mb .mb-corporate-list{display:flex;flex-direction:column;gap:10px}',
    '.mb .mb-corporate-row{display:grid;grid-template-columns:minmax(0,1fr) auto auto;gap:8px;padding:10px 0;border-bottom:1px solid var(--mb-line)}',
    '.mb .mb-corporate-row>strong,.mb .mb-corporate-row>span{grid-column:1/-1;overflow-wrap:anywhere}',
    '.mb .mb-corporate-status{display:flex;gap:6px;align-items:center;color:var(--mb-text-2)}',
    '.mb .mb-corporate-status[data-route="proxy"]{color:var(--mb-accent-text);background:var(--mb-accent-tint)}',
    '.mb .mb-corporate-status[data-warning="true"]{color:var(--mb-warn-text);background:var(--mb-warn-tint)}',
    '.mb .mb-corporate-editor{display:flex;flex-direction:column;gap:14px}',
    '.mb .mb-corporate-editor label{display:flex;flex-direction:column;gap:6px}',
  ].join(''),
);

function field(label, input) {
  return E('label', { class: 'mb-field' }, [E('span', {}, [label]), input]);
}

function edit(o, rule) {
  var original = rule || {
    id: 'corp_' + requestid.create(),
    name: '',
    address: '',
    port: '',
    enabled: 1,
    requires_udp: 1,
  };
  var name = E('input', { class: 'mb-input', value: original.name, maxlength: 128 });
  var address = E('input', { class: 'mb-input', value: original.address, inputmode: 'decimal' });
  var port = E('input', { class: 'mb-input', value: original.port, inputmode: 'numeric' });
  var enabled = E('input', { type: 'checkbox', checked: !!original.enabled });
  var udp = E('input', { type: 'checkbox', checked: !!original.requires_udp });
  var errors = E('div', { role: 'alert', class: 'mb-bad' });
  var save = E('button', { type: 'button', class: 'mb-btn mb-btn-primary' }, [_('Done')]);
  var s;

  save.addEventListener('click', function () {
    var next = {
      id: original.id,
      name: name.value,
      address: address.value,
      port: port.value,
      enabled: enabled.checked ? 1 : 0,
      requires_udp: udp.checked ? 1 : 0,
    };
    var candidate = o.candidate();

    var index = candidate.corporate_rules.findIndex(function (item) {
      return item.id === next.id;
    });

    if (index < 0) candidate.corporate_rules.push(next);
    else candidate.corporate_rules[index] = next;
    save.disabled = true;
    api
      .routingValidate(candidate)
      .then(function (result) {
        if (!result.valid) {
          errors.textContent = (result.items || [])
            .map(function (item) {
              return item.field + ': ' + item.code;
            })
            .join(' · ');
          var first = (result.items || [])[0];
          var inputs = { name: name, address: address, port: port };

          if (first && inputs[first.field]) inputs[first.field].focus();

          return;
        }
        o.change(candidate);
        s.close();
      })
      .catch(notice.fail(_('Validation failed: ')))
      .finally(function () {
        save.disabled = false;
      });
  });
  s = sheet.open({
    title: _('Corporate tunnel'),
    body: E('div', { class: 'mb-corporate-editor' }, [
      field(_('Name'), name),
      field(_('Gateway IPv4'), address),
      field(_('Port (optional)'), port),
      field(_('Via VPN'), enabled),
      field(_('Tunnel requires UDP'), udp),
      errors,
    ]),
    actions: [
      E(
        'button',
        {
          type: 'button',
          class: 'mb-btn',
          click: function () {
            s.close();
          },
        },
        [_('Cancel')],
      ),
      save,
    ],
  });
}

function policyText(policy, enabled) {
  if (!enabled) return _('Direct: VPN is off');
  if (!policy) return _('Not applied');
  if (policy.route === 'proxy') return _('Via VPN');
  var reasons = {
    rule_off: _('Direct'),
    https_down: _('Direct: VPN unavailable'),
    udp_down: _('Direct: UDP targets did not respond'),
    return_cooldown: _('Direct: waiting to return'),
    stale_monitor: _('Direct: monitor stale'),
    awaiting_health: _('Direct: waiting for VPN'),
  };

  return reasons[policy.reason] || _('Direct');
}

return baseclass.extend({
  render: function (o) {
    var list = E('div', { class: 'mb-corporate-list' });
    var removed = [];

    function update(snapshot, dirty) {
      var candidate = o.candidate();

      if (!dirty) removed = [];
      var rows = candidate.corporate_rules.map(function (rule) {
        var policy = (snapshot.effective_policy || {})[rule.id];
        var icon = E('span');
        var appliedRule = (snapshot.candidate.corporate_rules || []).find(function (item) {
          return item.id === rule.id;
        });
        var changed = JSON.stringify(appliedRule) !== JSON.stringify(rule);
        var toggle = E('input', {
          type: 'checkbox',
          checked: !!rule.enabled,
          disabled: o.readonly,
          'aria-label': _('Via VPN'),
        });

        toggle.addEventListener('change', function () {
          rule.enabled = toggle.checked ? 1 : 0;
          o.change(candidate);
        });

        icon.innerHTML = policy && policy.route === 'proxy' ? icons.ARROW : icons.WARN;

        return E('div', { class: 'mb-corporate-row' }, [
          E('strong', {}, [rule.name]),
          E('span', {}, [rule.address + (rule.port ? ':' + rule.port : '')]),
          E(
            'span',
            {
              class: 'mb-corporate-status',
              'data-route': policy && policy.route,
              'data-warning': String(!!(!changed && policy && policy.route === 'direct' && rule.enabled)),
            },
            [
              icon,
              snapshot.runtime_error
                ? _('Routing state could not be verified')
                : changed
                  ? _('Not applied')
                  : policyText(policy, snapshot.enabled),
            ],
          ),
          field(_('Via VPN'), toggle),
          E(
            'button',
            {
              type: 'button',
              class: 'mb-btn',
              disabled: o.readonly,
              click: function () {
                edit(o, rule);
              },
            },
            [_('Edit')],
          ),
          E(
            'button',
            {
              type: 'button',
              class: 'mb-btn',
              disabled: o.readonly,
              click: function () {
                removed.push(rule);
                candidate.corporate_rules = candidate.corporate_rules.filter(function (item) {
                  return item.id !== rule.id;
                });
                o.change(candidate);
                notice.show(_('Removed from draft. Discard changes to undo.'), 'info');
              },
            },
            [_('Remove')],
          ),
        ]);
      });

      removed.forEach(function (rule) {
        rows.push(
          E('div', {}, [
            E('span', {}, [rule.name + ' · ' + _('Removed from draft')]),
            E(
              'button',
              {
                type: 'button',
                class: 'mb-btn',
                click: function () {
                  removed = removed.filter(function (item) {
                    return item.id !== rule.id;
                  });
                  candidate.corporate_rules.push(rule);
                  o.change(candidate);
                },
              },
              [_('Undo')],
            ),
          ]),
        );
      });
      if (!rows.length) rows.push(E('p', { class: 'mb-muted' }, [_('No corporate rules configured')]));
      dom.content(list, rows);
    }

    return {
      node: E('section', {}, [
        E('h3', {}, [_('Corporate tunnels')]),
        list,
        E(
          'button',
          {
            type: 'button',
            class: 'mb-btn',
            disabled: o.readonly,
            click: function () {
              edit(o);
            },
          },
          [_('Add')],
        ),
      ]),
      update: update,
    };
  },
});
