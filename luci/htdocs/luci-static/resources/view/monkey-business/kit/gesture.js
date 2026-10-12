'use strict';
'require baseclass';

var down = false;
var queue = [];

function done() {
  var run = queue;

  down = false;
  queue = [];
  if (run.length)
    setTimeout(function () {
      run.forEach(function (fn) {
        fn();
      });
    }, 0);
}

document.addEventListener(
  'pointerdown',
  function () {
    down = true;
  },
  true,
);
document.addEventListener('pointerup', done, true);
document.addEventListener('pointercancel', done, true);
document.addEventListener('contextmenu', done, true);
window.addEventListener('blur', done);

return baseclass.extend({
  after: function (fn) {
    if (!down) return fn();
    if (queue.indexOf(fn) < 0) queue.push(fn);
  },
});
