'use strict';
'require baseclass';
'require view.monkey-business.store as store';
'require view.monkey-business.kit.notify as notice';
'require view.monkey-business.model.servers as model';
'require view.monkey-business.model.order as order';

return baseclass.extend({
  create: function (o) {
    var st = o.st;

    function move(sid, target, after) {
      store.move(sid, target, after);
    }

    function place(sid, target) {
      var r = order.place(o.ids(), sid, target);

      if (r) move(sid, target, r.after);
      o.changed();
    }

    function step(sid, dir) {
      var target = order.neighbour(o.ids(), sid, dir);

      if (!target) return;
      move(sid, target, dir > 0);
      o.changed();
    }

    function tap(sid) {
      var from = st.picked;

      st.picked = from == null ? sid : null;
      if (from != null && from !== sid) return place(from, sid);
      o.draw();
    }

    function sort() {
      var now = o.ids();
      var want = order.sorted(now, function (sid) {
        return model.rank(o.pingOf(store.get(sid)));
      });

      if (want.join() === now.join()) return notice.show(_('Already in ping order.'), 'info');
      order.chain(want, move);
      o.changed();
      notice.show(_('Sorted by ping. Press “Save & Apply” to connect in this order.'), 'info');
    }

    return { place: place, step: step, tap: tap, sort: sort };
  },
});
