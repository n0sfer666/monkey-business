'use strict';
'require baseclass';
'require ui';

function show(text, level) {
  ui.addNotification(null, E('p', {}, [text]), level);
}

return baseclass.extend({
  show: show,

  fail: function (prefix) {
    return function (e) {
      show(prefix + ((e && e.message) || e), 'error');
    };
  },
});
