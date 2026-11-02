'use strict';
'require baseclass';
'require view.monkey-business.availability as availability';
'require dom';
'require view.monkey-business.pingtext as pingtext';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.kit.icons as icons';
'require view.monkey-business.kit.seg as seg';
'require view.monkey-business.kit.refocus as refocus';
'require view.monkey-business.model.servers as model';
'require view.monkey-business.dash.servergroups as groups';
'require view.monkey-business.dash.serverrow as serverrow';
'require view.monkey-business.dash.serveracts as acts';

style.add(
  'dash-servers',
  [
    '.mb .mb-dash-servers{display:flex;flex-direction:column;min-width:0}',
    '.mb .mb-dash-shd{display:flex;align-items:center;gap:12px;padding:10px 12px;border-bottom:1px solid var(--mb-line)}',
    '.mb .mb-dash-segbox{min-width:0;overflow:hidden}',
    '.mb .mb-dash-empty{padding:12px;color:var(--mb-muted)}',
    style.MOBILE + '{',
    '.mb .mb-dash-servers{border-radius:10px}',
    '.mb .mb-dash-shd{flex-wrap:wrap;gap:10px 8px;border-bottom:0}',
    '.mb .mb-dash-shd h2{flex-grow:1;font-size:15px}',
    '.mb .mb-dash-shd>.mb-dash-grow{display:none}',
    '.mb .mb-dash-shd .mb-btn.mb-dash-srvbtn{width:36px;height:36px;padding:0;border-radius:6px}',
    '.mb .mb-dash-segbox{order:1;flex-basis:100%}',
    '}',
  ].join(''),
);

function headButton(text, svg, run, off) {
  var btn = E('button', {
    type: 'button',
    class: 'mb-btn mb-btn-sm mb-dash-srvbtn',
    'aria-label': text,
    disabled: off ? '' : null,
    click: run,
  });

  btn.innerHTML = svg;
  btn.appendChild(E('span', { class: 'mb-dash-wide' }, [text]));

  return btn;
}

function mark(btn, on) {
  if (on) btn.setAttribute('aria-disabled', 'true');
  else btn.removeAttribute('aria-disabled');
}

function sig(list, active) {
  return JSON.stringify(
    [active].concat(
      list.map(function (s) {
        return [availability.key(availability.ref(s)), s.tag, s.disabled, s.availability, model.protocol(s)];
      }),
    ),
  );
}

return baseclass.extend({
  render: function (o) {
    var servers = [];
    var st = {};
    var filter = null;
    var shownKey = null;
    var groupKey = null;
    var rows = {};
    var busy = {};
    var segBox = E('div', { class: 'mb-dash-segbox' });
    var pingAllBtn = headButton(
      _('Ping all'),
      icons.PULSE,
      function () {
        hold('pingAll', function () {
          return acts.pingAll(apply);
        });
      },
      o.readonly,
    );
    var sortBtn = headButton(
      _('Sort by ping'),
      icons.SORT,
      function () {
        hold('write', function () {
          return acts.sort(shown(), byId, st.enabled).then(o.onChanged);
        });
      },
      o.readonly,
    );
    var list = E('div', { role: 'list' });
    var head = E('div', { class: 'mb-dash-shd' }, [
      E('h2', {}, [_('Servers')]),
      segBox,
      E('div', { class: 'mb-dash-grow' }),
      pingAllBtn,
      sortBtn,
    ]);
    var card = E('section', { class: 'mb-panel mb-dash-servers', 'aria-label': _('Servers') }, [
      head,
      serverrow.head(),
      list,
    ]);

    function byId(id) {
      return model.byId(servers, id);
    }
    function rowKey(server) {
      return availability.key(availability.ref(server));
    }
    function byRef(ref) {
      return servers.find(function (server) {
        return rowKey(server) === availability.key(ref);
      });
    }

    function shown() {
      return servers.filter(function (s) {
        return groups.inGroup(s, filter);
      });
    }

    function repaint() {
      mark(pingAllBtn, busy.pingAll);
      mark(sortBtn, busy.write);
      shownKey = null;
      drawRows();
    }

    function hold(key, fn) {
      if (busy[key]) return;
      busy[key] = true;
      repaint();
      Promise.resolve()
        .then(fn)
        .finally(function () {
          delete busy[key];
          repaint();
        });
    }

    function apply(res) {
      pingtext.results(res).forEach(function (r) {
        var s = r.server_ref ? byRef(r.server_ref) : byId(r.id);

        if (!s) return;
        s.latency_ms = r.latency_ms;
        s.ping_na = r.na;
        s.auto_disabled = false;
        s.availability = r.availability;
        if (rows[rowKey(s)]) rows[rowKey(s)].ping(s);
      });
    }

    var rowActs = {
      onPing: function (s) {
        if (o.readonly) return;
        hold('ping:' + rowKey(s), function () {
          return acts.ping(s, apply);
        });
      },
      onConnect: function (s) {
        if (!s.disabled && !o.readonly)
          hold('write', function () {
            return acts.connect(s).then(o.onChanged);
          });
      },
    };

    function drawRows() {
      var active = (st.running || st.enabled) && st.server_ref ? availability.key(st.server_ref) : null;
      var items = shown();
      var key = filter + '|' + sig(items, active);

      if (key === shownKey) return;
      shownKey = key;
      rows = {};
      refocus.around(list, { pattern: /^mb-dash-s(ping|go)$/, attr: 'data-id' }, function () {
        dom.content(
          list,
          items.length
            ? items.map(function (s, i) {
                var row = serverrow.render(
                  s,
                  i,
                  Object.assign(
                    {
                      active: rowKey(s) === active,
                      pinging: !!busy['ping:' + rowKey(s)],
                      locked: !!busy.write || !!o.readonly,
                    },
                    rowActs,
                  ),
                );

                rows[rowKey(s)] = row;
                row.node.setAttribute('role', 'listitem');

                return row.node;
              })
            : E('div', { class: 'mb-dash-empty' }, [_('No servers in this group.')]),
        );
      });
    }

    function drawGroups() {
      var opts = groups.of(servers, st);

      filter = groups.pick(opts, filter, st.active_sub);
      var key = JSON.stringify(
        opts.map(function (g) {
          return [g.value, g.text];
        }),
      );

      if (key === groupKey) return;
      groupKey = key;
      dom.content(
        segBox,
        opts.length > 1
          ? seg.render({
              label: _('Server group'),
              compact: true,
              options: opts,
              value: filter,
              onChange: function (v) {
                filter = v;
                drawRows();
              },
            })
          : '',
      );
      segBox.hidden = opts.length < 2;
    }

    return {
      node: card,
      update: function (nextServers, nextSt) {
        servers = nextServers || [];
        st = nextSt || {};
        drawGroups();
        drawRows();
      },
    };
  },
});
