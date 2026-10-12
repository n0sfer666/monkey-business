'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';

var FADE = 36;

style.add(
  'overflow',
  [
    '.mb .mb-ovf{position:relative;display:inline-flex;max-width:100%;min-width:0;vertical-align:middle}',
    '.mb .mb-ovf>:first-child{min-width:0;flex:1 1 auto;scroll-padding-inline:' + FADE + 'px}',
    '.mb .mb-ovf-arrow{position:absolute;top:1px;bottom:1px;z-index:1;display:flex;align-items:center;width:' +
      FADE +
      'px;',
    'color:var(--mb-muted);cursor:pointer;user-select:none;-webkit-user-select:none}',
    '.mb .mb-ovf-arrow:hover{color:var(--mb-text)}',
    '.mb .mb-ovf-arrow[hidden]{display:none}',
    '.mb .mb-ovf-arrow svg{display:block;width:16px;height:16px}',
    '.mb .mb-ovf-prev{left:1px;justify-content:flex-start;padding-left:4px;border-radius:5px 0 0 5px;',
    'background:linear-gradient(to right,var(--mb-bg) 22px,transparent)}',
    '.mb .mb-ovf-next{right:1px;justify-content:flex-end;padding-right:4px;border-radius:0 5px 5px 0;',
    'background:linear-gradient(to left,var(--mb-bg) 22px,transparent)}',
    style.MOBILE + '{.mb .mb-ovf{display:flex}}',
  ].join(''),
);

var CHEVRONS = { '-1': 'M15 6l-6 6 6 6', 1: 'M9 6l6 6-6 6' };

function arrow(scroller, dir) {
  var a = E('span', {
    class: 'mb-ovf-arrow ' + (dir < 0 ? 'mb-ovf-prev' : 'mb-ovf-next'),
    'aria-hidden': 'true',
    hidden: '',
  });

  a.innerHTML =
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" ' +
    'stroke-linejoin="round"><path d="' +
    CHEVRONS[dir] +
    '"/></svg>';
  a.addEventListener('click', function () {
    scroller.scrollBy({ left: dir * Math.max(scroller.clientWidth - 2 * FADE, FADE), behavior: 'smooth' });
  });

  return a;
}

function reveal(scroller, item) {
  if (item.offsetLeft - FADE < scroller.scrollLeft) scroller.scrollLeft = item.offsetLeft - FADE;
  else if (item.offsetLeft + item.offsetWidth + FADE > scroller.scrollLeft + scroller.clientWidth)
    scroller.scrollLeft = item.offsetLeft + item.offsetWidth + FADE - scroller.clientWidth;
}

return baseclass.extend({
  wrap: function (scroller, current) {
    var prev = arrow(scroller, -1);
    var next = arrow(scroller, 1);

    function edges() {
      var max = scroller.scrollWidth - scroller.clientWidth;

      prev.hidden = scroller.scrollLeft <= 1;
      next.hidden = scroller.scrollLeft >= max - 1;
    }

    scroller.addEventListener('scroll', edges, { passive: true });
    if (window.ResizeObserver)
      new ResizeObserver(function () {
        var item = current();

        if (item) reveal(scroller, item);
        edges();
      }).observe(scroller);
    requestAnimationFrame(edges);

    return E('div', { class: 'mb-ovf' }, [scroller, prev, next]);
  },
});
