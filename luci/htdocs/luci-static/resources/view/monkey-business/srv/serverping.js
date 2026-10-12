'use strict';
'require baseclass';
'require view.monkey-business.api as api';
'require view.monkey-business.store as store';
'require view.monkey-business.subs as subs';
'require view.monkey-business.kit.notify as notice';
'require view.monkey-business.model.servers as model';

return baseclass.extend({
  create: function (st, draw) {
    function update(results) {
      (results || []).forEach(function (r) {
        st.pings[r.id] = model.pingOf(r);
        st.known[r.id] = true;
      });
    }

    function of(s) {
      return st.pings[subs.serverId(s)];
    }

    function all() {
      if (st.pinging) return Promise.resolve();
      st.pinging = true;

      return api
        .serversPing()
        .then(function (res) {
          if (res && res.error) return notice.show(_('Latency test failed: ') + res.error, 'warning');
          update(res && res.results);
        })
        .catch(notice.fail(_('Latency test failed: ')))
        .finally(function () {
          st.pinging = false;
        })
        .then(draw);
    }

    function one(sid) {
      var id = subs.serverId(store.get(sid));

      return api
        .serverPing(id)
        .then(function (r) {
          if (r && r.error) return notice.show(_('Ping failed: ') + r.error, 'warning');
          update([r]);
          draw();
        })
        .catch(notice.fail(_('Ping failed: ')));
    }

    return { update: update, of: of, all: all, one: one };
  },
});
