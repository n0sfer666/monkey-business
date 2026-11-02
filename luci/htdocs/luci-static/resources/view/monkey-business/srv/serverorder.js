'use strict';
'require baseclass';
'require view.monkey-business.store as store';
'require view.monkey-business.kit.notify as notice';
'require view.monkey-business.model.servers as model';
'require view.monkey-business.model.order as order';
'require view.monkey-business.subs as subs';

return baseclass.extend({
  create: function (o) {
    var st = o.st;

    function move(sid, target, after) {
      store.move(sid, target, after);
    }

    function place(sid, target) {
      if (subs.serverSub(store.get(sid)) !== subs.serverSub(store.get(target))) return;
      var all = o.ids();
      var group = all.filter(function (id) {
        return subs.serverSub(store.get(id)) === subs.serverSub(store.get(sid));
      });
      var r = order.place(group, sid, target);

      if (r) {
        group.splice(group.indexOf(sid), 1);
        group.splice(group.indexOf(target) + (r.after ? 1 : 0), 0, sid);
        var at = 0;

        order.chain(
          all.map(function (id) {
            return group.indexOf(id) >= 0 ? group[at++] : id;
          }),
          move,
        );
      }
      o.changed();
    }

    function step(sid, dir) {
      var group = o.ids().filter(function (id) {
        return subs.serverSub(store.get(id)) === subs.serverSub(store.get(sid));
      });
      var target = order.neighbour(group, sid, dir);

      if (!target) return;
      place(sid, target);
    }

    function tap(sid) {
      var from = st.picked;

      st.picked = from == null ? sid : null;
      if (from != null && from !== sid) return place(from, sid);
      o.draw();
    }

    function sort() {
      var now = o.ids();
      var groups = {};

      now.forEach(function (sid) {
        var key = subs.serverSub(store.get(sid)) || '';

        if (!groups[key]) groups[key] = [];
        groups[key].push(sid);
      });
      Object.keys(groups).forEach(function (key) {
        groups[key] = order.sorted(groups[key], function (sid) {
          return model.rank(o.pingOf(store.get(sid)));
        });
      });
      var want = now.map(function (sid) {
        return groups[subs.serverSub(store.get(sid)) || ''].shift();
      });

      if (want.join() === now.join()) return notice.show(_('Already in ping order.'), 'info');
      order.chain(want, move);
      o.changed();
      notice.show(_('Sorted by availability. Press “Apply priority” to save for the next connection.'), 'info');
    }

    return { place: place, step: step, tap: tap, sort: sort };
  },
});
