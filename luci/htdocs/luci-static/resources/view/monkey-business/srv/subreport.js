'use strict';
'require baseclass';
'require view.monkey-business.kit.notify as notice';

return baseclass.extend({
  fetch: function (name, res) {
    if (res && res.error)
      return notice.show(_('Subscription “%s” update failed: %s').format(name, res.error), 'warning');
    notice.show(_('Servers fetched for “%s”: %d').format(name, (res && res.added) || 0), 'info');
  },

  ping: function (res) {
    if (res && res.error) return notice.show(_('Ping failed: ') + res.error, 'warning');
    var results = (res && res.results) || [];
    var count = function (pred) {
      return results.filter(pred).length;
    };

    notice.show(
      _('Availability: %d available, %d degraded, %d other').format(
        count(function (r) {
          return r.state === 'available';
        }),
        count(function (r) {
          return r.state === 'degraded';
        }),
        count(function (r) {
          return ['available', 'degraded'].indexOf(r.state) < 0;
        }),
      ),
      'info',
    );
  },
});
