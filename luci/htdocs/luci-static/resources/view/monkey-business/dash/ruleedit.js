'use strict';
'require baseclass';
'require dom';

function lines(text) {
	return String(text).split('\n').length;
}

return baseclass.extend({
	render: function(o) {
		var nums = E('div', { 'class': 'mb-cr-gin' });
		var marks = E('div', { 'class': 'mb-cr-hin' });
		var bad = {};
		var ta = E('textarea', {
			'id': o.id,
			'class': 'mb-cr-ta',
			'wrap': 'off',
			'spellcheck': 'false',
			'autocomplete': 'off',
			'autocapitalize': 'off',
			'aria-label': o.label,
			'aria-invalid': 'false',
			'placeholder': o.placeholder
		});
		var box = E('div', { 'class': 'mb-cr-box' }, [
			E('div', { 'class': 'mb-cr-gut', 'aria-hidden': 'true' }, [ nums ]),
			E('div', { 'class': 'mb-cr-area' }, [ E('div', { 'class': 'mb-cr-hl', 'aria-hidden': 'true' }, [ marks ]), ta ])
		]);

		function paint() {
			var n = lines(ta.value);
			var rows = [], fills = [];
			for (var i = 1; i <= n; i++) {
				rows.push(E('div', { 'class': bad[i] ? 'mb-cr-bad' : null }, [ String(i) ]));
				fills.push(E('div', { 'class': bad[i] ? 'mb-cr-bad' : null }));
			}
			dom.content(nums, rows);
			dom.content(marks, fills);
		}

		function scroll() {
			var y = 'translateY(' + (-ta.scrollTop) + 'px)';
			nums.style.transform = y;
			marks.style.transform = y;
		}

		ta.value = o.value || '';
		ta.addEventListener('input', paint);
		ta.addEventListener('scroll', scroll);
		paint();

		return {
			node: box,
			textarea: ta,
			mark: function(items, describedby) {
				bad = {};
				items.forEach(function(i) { bad[i.line] = true; });
				var invalid = items.length > 0;
				box.classList.toggle('mb-bad', invalid);
				ta.setAttribute('aria-invalid', invalid ? 'true' : 'false');
				if (invalid)
					ta.setAttribute('aria-describedby', describedby);
				else
					ta.removeAttribute('aria-describedby');
				paint();
				scroll();
			}
		};
	}
});
