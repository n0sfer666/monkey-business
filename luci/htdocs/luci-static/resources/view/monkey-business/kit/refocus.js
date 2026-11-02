'use strict';
'require baseclass';

function classOf(el, pattern) {
  return Array.prototype.find.call(el.classList, function (c) {
    return pattern.test(c);
  });
}

function within(el, sel, attr) {
  var scope = el.closest('[' + attr + ']');

  if (!scope) return sel;
  var at = '[' + attr + '="' + CSS.escape(scope.getAttribute(attr)) + '"]';

  return scope === el ? sel + at : at + ' ' + sel;
}

function remember(root, o) {
  var el = document.activeElement;
  var cls = el && root.contains(el) ? classOf(el, o.pattern) : null;

  if (!cls) return null;
  var val = el.getAttribute('data-value');
  var sel = '.' + cls + (val ? '[data-value="' + CSS.escape(val) + '"]' : '');

  return { sel: sel, exact: within(el, sel, o.attr), at: Array.prototype.indexOf.call(root.querySelectorAll(sel), el) };
}

function shown(el) {
  return !!(el && el.getClientRects().length);
}

function restore(root, key, spare) {
  var all = root.querySelectorAll(key.sel);
  var to = root.querySelector(key.exact) || all[Math.min(key.at, all.length - 1)] || (spare && spare());

  if (to) to.focus();
}

return baseclass.extend({
  around: function (root, o, paint) {
    var key = remember(root, o);

    paint();
    if (key) restore(root, key, o.spare);
  },

  near: function (root, attr, id, classes, spare) {
    return function () {
      var scope = root.querySelector('[' + attr + '="' + CSS.escape(id) + '"]');
      var hit =
        scope &&
        classes
          .map(function (c) {
            return scope.querySelector('.' + c);
          })
          .find(shown);

      return hit || root.querySelector(spare);
    };
  },
});
