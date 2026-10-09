'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.kit.sheet as sheet';

style.add('confirm', [
	'.mb .mb-confirm-ico{display:flex;align-items:center;justify-content:center;flex-shrink:0;width:36px;height:36px;',
	'border-radius:50%;background:var(--mb-err-tint);color:var(--mb-err-text)}',
	'.mb .mb-confirm-body{color:var(--mb-text-2)}'
].join(''));

var TRASH = '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">' +
	'<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"></path></svg>';

var KIND = { 'cancel': 'mb-btn', 'second': 'mb-btn', 'danger': 'mb-btn mb-btn-danger', 'primary': 'mb-btn mb-btn-primary' };

function icon() {
	var el = E('div', { 'class': 'mb-confirm-ico' });
	el.innerHTML = TRASH;
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
				icon: o.danger === false ? '' : icon(),
				title: o.title,
				closable: false,
				body: o.body ? E('div', { 'class': 'mb-confirm-body' }, [ o.body ]) : null,
				actions: actions,
				onClose: function() { finish(null); }
			});
		});
	}
});
