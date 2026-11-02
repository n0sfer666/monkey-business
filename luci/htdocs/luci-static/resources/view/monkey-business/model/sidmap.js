'use strict';
'require baseclass';

function options(s) {
  return Object.keys(s)
    .filter(function (k) {
      return k.charAt(0) !== '.';
    })
    .sort();
}

function same(a, b) {
  var ka = options(a);
  var kb = options(b);

  return (
    a['.type'] === b['.type'] &&
    ka.join('\n') === kb.join('\n') &&
    ka.every(function (k) {
      return JSON.stringify(a[k]) === JSON.stringify(b[k]);
    })
  );
}

return baseclass.extend({
  match: function (made, fresh) {
    var names = {};
    var free = fresh.slice();

    Object.keys(made).forEach(function (temp) {
      var at = free.findIndex(function (s) {
        return same(made[temp], s);
      });

      if (at < 0) return;
      names[temp] = free[at]['.name'];
      free.splice(at, 1);
    });

    return names;
  },

  order: function (want, names, real) {
    return want
      .map(function (sid) {
        return names[sid] || sid;
      })
      .filter(function (sid) {
        return real.indexOf(sid) >= 0;
      });
  },
});
