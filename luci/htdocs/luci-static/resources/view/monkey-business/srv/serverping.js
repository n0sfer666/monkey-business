'use strict';
'require baseclass';
'require view.monkey-business.availability as availability';
'require view.monkey-business.store as store';
'require view.monkey-business.kit.notify as notice';
'require view.monkey-business.model.servers as model';

return baseclass.extend({
  create: function (st, draw) {
    function update(results) {
      (results || []).forEach(function (r) {
        var key = availability.key(r.server_ref);

        st.pings[key] = model.pingOf(r);
        st.known[key] = true;
      });
    }

    function of(s) {
      return st.pings[availability.key(availability.ref(s))];
    }

    function all() {
      if (st.pinging) return Promise.resolve();
      st.pinging = true;

      return availability
        .run('all')
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
      var id = store.get(sid);

      return availability
        .one(id)
        .then(function (r) {
          if (r && r.error) return notice.show(_('Ping failed: ') + r.error, 'warning');
          update(r && r.results);
          draw();
        })
        .catch(notice.fail(_('Ping failed: ')));
    }

    return { update: update, of: of, all: all, one: one };
  },
});
