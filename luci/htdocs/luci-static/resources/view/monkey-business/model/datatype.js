'use strict';
'require baseclass';

return baseclass.extend({
  port: function (value) {
    var n = /^[0-9]{1,5}$/.test(value) ? parseInt(value, 10) : 0;

    if (n >= 1 && n <= 65535) return null;

    return _('Enter a number from 1 to 65535');
  },
});
