'use strict';
'require baseclass';
'require dom';
'require uci';
'require view.monkey-business.api as api';
'require view.monkey-business.store as store';
'require view.monkey-business.kit.guard as guard';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.kit.notify as notice';
'require view.monkey-business.model.routing as model';

style.add(
  'dash-routing',
  [
    '.mb .mb-dash-routing{display:flex;flex-direction:column;gap:10px;padding:12px 14px}',
    '.mb .mb-dash-rhead{display:flex;align-items:center;justify-content:space-between}',
    '.mb .mb-btn.mb-dash-rsave{padding:4px 12px;font-weight:400}',
    '.mb .mb-dash-rfield{display:flex;align-items:center;gap:10px}',
    '.mb .mb-dash-rfield>label{flex-shrink:0;width:52px;color:var(--mb-muted);font-size:12px}',
    '.mb select.mb-input.mb-dash-rsel{width:auto;padding:5px 30px 5px 10px}',
    '.mb .mb-dash-chips{display:flex;flex-wrap:wrap;gap:6px}',
    '.mb .mb-dash-chips>span{padding:2px 8px;background:var(--mb-bg);border:1px solid var(--mb-line);border-radius:4px;color:var(--mb-text-2)}',
    '.mb .mb-dash-rules{display:flex;align-items:center;gap:10px;padding-top:10px;border-top:1px solid var(--mb-line)}',
    '.mb .mb-dash-rules>div{display:flex;align-items:center;gap:10px;flex-grow:1;min-width:0}',
    '.mb .mb-dash-rules>div>span:first-child{font-weight:500}',
    '.mb .mb-btn.mb-dash-redit{padding:5px 12px}',
    style.MOBILE + '{',
    '.mb .mb-dash-routing{padding:14px;border-radius:10px}',
    '.mb .mb-dash-rhead{display:contents}',
    '.mb .mb-dash-rhead h2{font-size:15px}',
    '.mb .mb-btn.mb-dash-rsave{order:1;width:100%;padding:10px 0;font-weight:600}',
    '.mb select.mb-input.mb-dash-rsel{padding:7px 32px 7px 10px}',
    '.mb .mb-dash-chips>span{font-size:12px}',
    '.mb .mb-dash-rules>div{flex-direction:column;align-items:flex-start;gap:2px}',
    '.mb .mb-dash-rules>div>span:last-child{font-size:12px}',
    '.mb .mb-btn.mb-dash-redit{padding:8px 14px}',
    '}',
  ].join(''),
);

function select(id, options, readonly) {
  return E(
    'select',
    { id: id, class: 'mb-input mb-dash-rsel', disabled: readonly ? '' : null },
    options.map(function (o) {
      return E('option', { value: o.value }, [o.label]);
    }),
  );
}

function field(id, label, el) {
  return E('div', { class: 'mb-dash-rfield' }, [E('label', { for: id }, [label]), el]);
}

function applied(res) {
  if (res && res.error) return notice.show(_('Apply failed: ') + res.error, 'warning');
  if (res && res.skipped === 'disabled')
    return notice.show(_('Saved. The VPN is off — the split applies when you turn it on.'), 'info');
  notice.show(_('Routing mode applied.'), 'info');
}

return baseclass.extend({
  render: function (o) {
    var mode = select('mb-dash-mode', model.MODES, o.readonly);
    var region = select('mb-dash-region', model.REGIONS, o.readonly);
    var last = {};
    var chips = E('div', { class: 'mb-dash-chips', 'aria-live': 'polite' });
    var counts = E('span', { class: 'mb-muted' });
    var save = E(
      'button',
      { type: 'button', class: 'mb-btn mb-btn-primary mb-dash-rsave', disabled: o.readonly ? '' : null },
      [_('Save & Apply')],
    );
    var edit = E(
      'button',
      {
        type: 'button',
        class: 'mb-btn mb-dash-redit',
        'aria-haspopup': 'dialog',
        disabled: o.readonly ? '' : null,
        click: o.onEdit,
      },
      [_('Edit')],
    );

    function paintChips() {
      dom.content(
        chips,
        model.chips(mode.value, region.value).map(function (text) {
          return E('span', {}, [text]);
        }),
      );
    }

    function put(sel, value) {
      if (last[sel.id] == null || sel.value === last[sel.id]) sel.value = value;
      last[sel.id] = value;
    }

    function update() {
      put(mode, uci.get(store.CONF, 'global', 'routing_mode') || 'bypass-local');
      put(region, uci.get(store.CONF, 'global', 'local_region') || 'ru');
      counts.textContent = _('Direct %d · Via VPN %d').format(
        model.count(uci.get(store.CONF, 'global', 'custom_direct')),
        model.count(uci.get(store.CONF, 'global', 'custom_proxy')),
      );
      paintChips();
    }

    mode.addEventListener('change', paintChips);
    region.addEventListener('change', paintChips);
    save.addEventListener('click', function () {
      guard.run(save, function () {
        return api
          .setMode(mode.value, region.value)
          .then(applied)
          .catch(notice.fail(_('Apply failed: ')))
          .then(o.onChanged);
      });
    });

    update();

    return {
      node: E('section', { class: 'mb-panel mb-dash-routing', 'aria-label': _('Routing') }, [
        E('div', { class: 'mb-dash-rhead' }, [E('h2', {}, [_('Routing')]), save]),
        field('mb-dash-mode', _('Mode'), mode),
        field('mb-dash-region', _('Region'), region),
        chips,
        E('div', { class: 'mb-dash-rules' }, [E('div', {}, [E('span', {}, [_('Custom rules')]), counts]), edit]),
      ]),
      update: update,
    };
  },
});
