'use strict';
'require baseclass';
'require dom';
'require view.monkey-business.api as api';
'require view.monkey-business.store as store';
'require view.monkey-business.subs as subs';
'require view.monkey-business.kit.drag as drag';
'require view.monkey-business.kit.refocus as refocus';
'require view.monkey-business.kit.menu as menu';
'require view.monkey-business.model.servers as model';
'require view.monkey-business.model.subs as submodel';
'require view.monkey-business.srv.serverrow as serverrow';
'require view.monkey-business.srv.servertiles as servertiles';
'require view.monkey-business.srv.serveredit as serveredit';
'require view.monkey-business.srv.serverhead as serverhead';
'require view.monkey-business.srv.serverping as serverping';
'require view.monkey-business.srv.serverorder as serverorder';

var FOCUS = /^mb-(srow|srvs|seg)-|^mb-tile$/;

return baseclass.extend({
  create: function (o) {
    var view = E('div', { class: 'mb-srvs-view' });
    var live = E('div', { class: 'mb-srvs-live', 'aria-live': 'polite' });
    var root = E('section', { class: 'mb-panel mb-srvs' }, [view, live]);
    var list = E('div', { role: 'list', 'aria-label': _('Servers') });
    var st = { filter: 'all', moving: false, picked: null, pinging: false, pings: {}, known: {} };
    var edit = serveredit.create({
      subName: subName,
      onChange: changed,
      blocked: function () {
        return !!root.closest('[inert]');
      },
      back: function (sid, cls) {
        return refocus.near(root, 'data-sid', sid, [cls, 'mb-srow-more'], '.mb-srvs-add');
      },
    });
    var ping = serverping.create(st, draw);
    var arrange = serverorder.create({ st: st, ids: ids, pingOf: ping.of, changed: changed, draw: draw });

    function subList() {
      return store.sections('subscription').map(function (s) {
        return { id: s['.name'], name: submodel.title(s) };
      });
    }

    function subName(s) {
      var id = subs.serverSub(s);

      return id == null ? null : subs.name(subList(), id);
    }

    function all() {
      return model.visible(
        store.sections('server'),
        subList().map(function (x) {
          return x.id;
        }),
      );
    }

    function ids() {
      return all().map(function (s) {
        return s['.name'];
      });
    }

    function changed() {
      draw();
      o.onChange();
    }

    function setOff(sid, on) {
      store.set(sid, 'disabled', on ? '1' : '0');
      changed();
    }

    function rows(servers) {
      var movable = st.filter === 'all' && !o.readonly;

      dom.content(
        list,
        model.filtered(servers, st.filter).map(function (s) {
          return serverrow.render({
            server: s,
            n: servers.indexOf(s) + 1,
            subName: subName(s),
            ping: model.ping(ping.of(s)),
            movable: movable,
            pingable: !!st.known[subs.serverId(s)],
            readonly: o.readonly,
            onStep: arrange.step,
            onOff: setOff,
            onPing: ping.one,
            onEdit: edit.edit,
            onDelete: edit.remove,
          });
        }),
      );

      return list;
    }

    function body(servers) {
      if (!servers.length)
        return [
          E('div', { class: 'mb-srvs-empty mb-muted' }, [
            _('No servers yet. Fetch a subscription or add a server by its link.'),
          ]),
        ];
      if (st.moving)
        return servertiles.render({
          servers: servers,
          picked: st.picked,
          onTap: arrange.tap,
          ping: function (s) {
            return model.ping(ping.of(s));
          },
        });

      return [serverhead.cols(), rows(servers)];
    }

    function draw() {
      menu.close();
      refocus.around(
        root,
        {
          pattern: FOCUS,
          attr: 'data-sid',
          spare: function () {
            return root.querySelector('.mb-srvs-add');
          },
        },
        paint,
      );
    }

    function relist() {
      return api.serversList().then(
        function (res) {
          ping.update(res && res.servers);
          draw();
        },
        function () {},
      );
    }

    function paint() {
      var servers = all();
      var opts = model.filters(servers, subList());

      if (
        !opts.some(function (f) {
          return f.value === st.filter;
        })
      )
        st.filter = 'all';
      live.textContent = st.moving ? servertiles.moving(servers, st.picked) : '';
      dom.content(
        view,
        [
          serverhead.render({
            count: servers.length,
            filters: opts,
            filter: st.filter,
            moving: st.moving,
            pinging: st.pinging,
            readonly: o.readonly,
            onFilter: function (v) {
              st.filter = v;
              st.moving = false;
              draw();
            },
            onGear: function () {
              st.moving = !st.moving;
              st.picked = null;
              draw();
            },
            onPingAll: ping.all,
            onSort: arrange.sort,
            onAdd: edit.add,
          }),
        ].concat(body(servers), o.readonly || !servers.length ? [] : serverhead.foot()),
      );
    }

    function relabel() {
      root.querySelectorAll('.mb-srow[data-sid]').forEach(function (row) {
        serverrow.relabel(row, store.get(row.getAttribute('data-sid')), subName);
      });
      serverhead.relabel(root, model.filters(all(), subList()));
    }

    drag.attach(list, { handle: '.mb-srow-grip', key: 'data-sid', onDrop: arrange.place });
    ping.update(o.list && o.list.servers);
    draw();

    return {
      node: root,
      draw: draw,
      relabel: relabel,
      forget: edit.forget,
      saved: edit.saved,
      reset: edit.reset,
      relist: relist,
      onPing: function (res) {
        ping.update(res && res.results);
        draw();
      },
    };
  },
});
