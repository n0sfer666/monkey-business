'use strict';
'require baseclass';
'require view.monkey-business.api as api';
'require view.monkey-business.kit.notify as notice';
'require view.monkey-business.model.servers as model';
'require view.monkey-business.dash.sortping as sortping';
'require view.monkey-business.dash.unsaved as unsaved';

function pinged(apply) {
  return function (res) {
    if (res && res.error) return notice.show(_('Latency test failed: ') + res.error, 'warning');
    apply(res);
  };
}

function connected(s, res) {
  if (res.unchanged) return notice.show(_('Already on %s.').format(s.tag), 'info');
  if (res.skipped === 'disabled')
    return notice.show(
      _('%s is now first. The VPN is off — it connects there when you turn it on.').format(s.tag),
      'info',
    );
  if (res.server_id && res.server_id !== s.id)
    return notice.show(
      _('%s did not answer — connected to %s instead.').format(s.tag, res.server || res.server_id),
      'warning',
    );
  notice.show(_('Connected to %s.').format(s.tag), 'info');
}

function sorted(res) {
  if (res.error) return notice.show(_('Not sorted: ') + res.error, 'warning');
  if (res.unchanged) return notice.show(_('Already sorted by ping.'), 'info');
  if (res.apply_error) return notice.show(_('Sorted by ping, but apply failed: ') + res.apply_error, 'warning');
  if (res.skipped === 'disabled')
    return notice.show(_('Sorted by ping. The VPN is off — the order applies when you turn it on.'), 'info');
  notice.show(_('Sorted by ping.'), 'info');
}

return baseclass.extend({
  pingAll: function (apply) {
    return api
      .serversPing()
      .then(pinged(apply))
      .catch(notice.fail(_('Latency test failed: ')));
  },

  ping: function (id, apply) {
    return api
      .serverPing(id)
      .then(pinged(apply))
      .catch(notice.fail(_('Latency test failed: ')));
  },

  connect: function (s) {
    return unsaved
      .check(false)
      .then(function (err) {
        return err ? { error: err } : api.serverConnect(s.id);
      })
      .then(function (res) {
        if (res && res.error) return notice.show(_('Not connected: ') + res.error, 'warning');
        connected(s, res || {});
      })
      .catch(notice.fail(_('Connect error: ')));
  },

  sort: function (items, byId, enabled) {
    var ids = items.map(function (s) {
      return s.id;
    });
    var rankOf = function (id) {
      return model.rank(model.pingOf(byId(id) || {}));
    };

    return sortping
      .sort(ids, rankOf, enabled)
      .then(function (res) {
        sorted(res || {});
      })
      .catch(notice.fail(_('Not sorted: ')));
  },
});
