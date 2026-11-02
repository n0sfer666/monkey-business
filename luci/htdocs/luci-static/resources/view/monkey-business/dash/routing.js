'use strict';
'require baseclass';
'require view.monkey-business.model.requestid as requestid';
'require view.monkey-business.api as api';
'require view.monkey-business.kit.guard as guard';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.model.routing as model';
'require view.monkey-business.model.routingdraft as routingdraft';
'require view.monkey-business.dash.corporate as corporate';
'require view.monkey-business.dash.rules as rules';
'require view.monkey-business.kit.confirm as confirm';

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
    { id: id, class: 'mb-input mb-dash-rsel', disabled: readonly },
    options.map(function (o) {
      return E('option', { value: o.value }, [o.label]);
    }),
  );
}

return baseclass.extend({
  render: function (o) {
    var snapshot = o.snapshot;
    var draft = routingdraft.create(snapshot);
    var mode = select('mb-dash-mode', model.MODES, o.readonly);
    var region = select('mb-dash-region', model.REGIONS, o.readonly);
    var message = E('p', { role: 'status', 'aria-live': 'polite', class: 'mb-muted' });
    var save = E('button', { type: 'button', class: 'mb-btn mb-btn-primary', disabled: o.readonly }, [
      _('Save & Apply'),
    ]);
    var discard = E('button', { type: 'button', class: 'mb-btn', disabled: o.readonly }, [_('Discard changes')]);
    var corporateView;
    var root;

    function paint() {
      var candidate = draft.candidate();

      mode.value = candidate.mode;
      region.value = candidate.region;
      corporateView.update(snapshot, draft.dirty());
      save.disabled = o.readonly || !draft.dirty();
      discard.disabled = o.readonly || !draft.dirty();
    }

    function change(candidate) {
      draft.replace(candidate);
      message.textContent = _('Not applied');
      paint();
    }

    function update(next) {
      if (!next || next.error || !next.candidate) return;
      snapshot = next;
      draft.observe(next);
      paint();
    }

    function changed() {
      var candidate = draft.candidate();

      candidate.mode = mode.value;
      candidate.region = region.value;
      change(candidate);
    }

    function openRules() {
      var candidate = draft.candidate();

      rules.open({
        direct: candidate.direct,
        proxy: candidate.proxy,
        onDraft: function (lists) {
          candidate.direct = lists.direct;
          candidate.proxy = lists.proxy;
          change(candidate);
        },
      });
    }

    save.addEventListener('click', function () {
      guard.run(save, function () {
        var payload = draft.payload(requestid.create());

        message.textContent = _('Applying…');

        return api
          .routingApply(payload.expected_revision, payload.request_id, payload.candidate)
          .then(function (result) {
            if (result.error) {
              message.textContent = _('Not applied: ') + result.error;

              return;
            }

            return api.routingGet().then(function (next) {
              draft.accept(next);
              snapshot = next;
              message.textContent = result.status === 'saved_disabled' ? _('Saved: VPN is off') : _('Applied');
              paint();
            });
          })
          .catch(function () {
            // Keep the same request ID on retry after a lost response.
            message.textContent = _('Response lost. Retry or reload applied status.');
          });
      });
    });
    discard.addEventListener('click', function () {
      draft.accept(snapshot);
      message.textContent = '';
      paint();
    });
    mode.addEventListener('change', changed);
    region.addEventListener('change', changed);
    corporateView = corporate.render({ readonly: o.readonly, candidate: draft.candidate, change: change });
    root = E('section', { class: 'mb-panel mb-dash-routing', 'aria-label': _('Routing') }, [
      E('h2', {}, [_('Routing')]),
      E('label', { for: mode.id }, [_('Mode')]),
      mode,
      E('label', { for: region.id }, [_('Region')]),
      region,
      E('button', { type: 'button', class: 'mb-btn', disabled: o.readonly, click: openRules }, [_('Custom rules')]),
      corporateView.node,
      message,
      save,
      discard,
    ]);
    function beforeUnload(event) {
      if (!root.isConnected || !draft.dirty()) return;
      event.preventDefault();
      event.returnValue = '';
    }
    function navigate(event) {
      var link = event.target.closest('a[href]');

      if (!root.isConnected) {
        document.removeEventListener('click', navigate, true);
        window.removeEventListener('beforeunload', beforeUnload);

        return;
      }
      if (!link || !draft.dirty() || (link.hash && link.pathname === location.pathname)) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      confirm
        .ask({
          danger: false,
          title: _('Unapplied routing changes'),
          body: _('Stay or discard changes?'),
          actions: [
            { kind: 'cancel', label: _('Stay'), value: false },
            { kind: 'primary', label: _('Discard changes'), value: true },
          ],
        })
        .then(function (yes) {
          if (!yes) return;
          draft.accept(snapshot);
          window.location.href = link.href;
        });
    }
    window.addEventListener('beforeunload', beforeUnload);
    document.addEventListener('click', navigate, true);
    paint();

    return { node: root, update: update };
  },
});
