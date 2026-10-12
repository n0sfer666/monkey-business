'use strict';
'require baseclass';
'require uci';
'require view.monkey-business.store as store';

function staged(all, conf) {
  return (all[conf] || []).length > 0;
}

function check(others) {
  return uci.changes().then(function (all) {
    var map = all || {};

    if (staged(map, store.CONF)) return _('the Servers tab has unsaved changes — save or discard them first');
    var rest = Object.keys(map).filter(function (conf) {
      return conf !== store.CONF && staged(map, conf);
    });

    if (others && rest.length)
      return _('other LuCI pages have unapplied changes (%s) — apply or revert them first').format(rest.join(', '));

    return null;
  });
}

return baseclass.extend({
  check: check,
});
