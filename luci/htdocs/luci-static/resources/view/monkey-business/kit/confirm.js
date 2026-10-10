'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.kit.sheet as sheet';
'require view.monkey-business.kit.icons as icons';

style.add('confirm', [
	'.mb .mb-confirm-ico{display:flex;align-items:center;justify-content:center;flex-shrink:0;width:36px;height:36px;',
	'border-radius:50%;background:var(--mb-err-disc);color:var(--mb-err-text)}',
	style.MOBILE + '{.mb .mb-confirm-ico{width:40px;height:40px}}'
].join(''));

var KIND = { 'cancel': 'mb-btn', 'second': 'mb-btn', 'danger': 'mb-btn mb-btn-danger', 'primary': 'mb-btn mb-btn-primary' };

function icon() {
	var el = E('div', { 'class': 'mb-confirm-ico' });
	el.innerHTML = icons.TRASH;
	return el;
}

return baseclass.extend({
	ask: function(o) {
		return new Promise(function(resolve) {
			var done = false;
			var s;

			function finish(value) {
				if (done)
					return;
				done = true;
				resolve(value);
				s.close();
			}

			var actions = o.actions.map(function(a) {
				return E('button', {
					'type': 'button',
					'class': KIND[a.kind] || KIND.second,
					'data-autofocus': a.kind === 'cancel' ? '' : null,
					'click': function() { finish(a.value); }
				}, [ a.label ]);
			});

			s = sheet.open({
				role: 'alertdialog',
				width: '440px',
				top: '250px',
				compact: true,
				icon: o.danger === false ? '' : icon(),
				title: o.title,
				hint: o.body,
				closable: false,
				back: o.back,
				actions: actions,
				onClose: function() { finish(null); }
			});
		});
	}
});
