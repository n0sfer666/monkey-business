'use strict';
'require baseclass';
'require view.monkey-business.kit.focusable as focusable';

var last = null;

document.addEventListener(
  'click',
  function (ev) {
    last = ev.target.closest ? ev.target.closest(focusable.SEL) : null;
    setTimeout(function () {
      last = null;
    }, 0);
  },
  true,
);

return baseclass.extend({
  back: function () {
    var at = document.activeElement;

    if (last && last.isConnected) return last;

    return at && at !== document.body ? at : null;
  },
});
