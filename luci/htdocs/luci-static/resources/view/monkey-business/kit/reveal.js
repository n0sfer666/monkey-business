'use strict';
'require baseclass';
'require view.monkey-business.kit.icons as icons';

return baseclass.extend({
  render: function (input, labels) {
    var btn = E('button', { type: 'button', class: 'mb-btn mb-icon', 'aria-pressed': 'false' });

    function sync() {
      var shown = input.type === 'text';

      btn.innerHTML = shown ? icons.EYE_OFF : icons.EYE;
      btn.setAttribute('aria-pressed', shown ? 'true' : 'false');
      btn.setAttribute('aria-label', shown ? labels.hide : labels.show);
      btn.title = btn.getAttribute('aria-label');
    }

    btn.addEventListener('click', function () {
      input.type = input.type === 'text' ? 'password' : 'text';
      sync();
    });
    sync();

    return btn;
  },
});
