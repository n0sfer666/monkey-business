'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.kit.guard as guard';

style.add(
  'busybtn',
  [
    '@keyframes mb-spin{to{transform:rotate(360deg)}}',
    '.mb .mb-spin{animation:mb-spin .8s linear infinite;flex-shrink:0}',
    '@media (prefers-reduced-motion:reduce){.mb .mb-spin{animation:none}}',
  ].join(''),
);

var SPIN =
  '<svg class="mb-spin" viewBox="0 0 24 24" width="14" height="14" fill="none" stroke-width="2.5" aria-hidden="true">' +
  '<circle cx="12" cy="12" r="9" style="stroke:var(--mb-line-strong)"></circle>' +
  '<path d="M21 12a9 9 0 0 0-9-9" style="stroke:var(--mb-accent)"></path></svg>';

function content(icon, text, cls) {
  var txt = E('span', { class: 'mb-btn-txt' }, [].concat(text));

  if (!icon) return [txt];
  var ico = E('span', { class: 'mb-btn-ico' + (cls ? ' ' + cls : '') });

  ico.innerHTML = icon;

  return [ico, txt];
}

function paint(btn, icon, text) {
  btn.textContent = '';
  btn.append.apply(btn, content(icon, text));
}

function hold(btn, o) {
  btn.setAttribute('aria-disabled', 'true');
  btn.setAttribute('aria-busy', 'true');
  paint(btn, o.icon ? SPIN : null, o.busy);
}

return baseclass.extend({
  content: content,

  render: function (o) {
    var btn = E('button', { type: 'button', class: 'mb-btn ' + (o.cls || '') });

    paint(btn, o.icon, o.label);
    if (o.pending) hold(btn, o);
    btn.addEventListener('click', function () {
      guard.run(btn, function () {
        hold(btn, o);

        return Promise.resolve(o.run()).finally(function () {
          paint(btn, o.icon, o.label);
        });
      });
    });

    return btn;
  },
});
