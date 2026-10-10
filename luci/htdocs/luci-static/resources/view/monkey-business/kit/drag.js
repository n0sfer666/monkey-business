'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';

style.add('drag', [
	'.mb .mb-drag-src{opacity:.4}',
	'.mb .mb-drag-before{box-shadow:inset 0 2px 0 var(--mb-accent)}',
	'.mb .mb-drag-after{box-shadow:inset 0 -2px 0 var(--mb-accent)}'
].join(''));

function follows(a, b) {
	return !!(a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING);
}

return baseclass.extend({
	attach: function(list, o) {
		var src = null;

		function itemOf(el) {
			return el && el.closest ? el.closest('[' + o.key + ']') : null;
		}

		function clear() {
			list.querySelectorAll('.mb-drag-before,.mb-drag-after').forEach(function(el) {
				el.classList.remove('mb-drag-before', 'mb-drag-after');
			});
		}

		function end() {
			if (src)
				src.classList.remove('mb-drag-src');
			src = null;
			clear();
		}

		function target(ev) {
			var it = itemOf(ev.target);
			return (src && it && it !== src && list.contains(it)) ? it : null;
		}

		list.addEventListener('dragstart', function(ev) {
			end();
			if (!ev.target.closest || !ev.target.closest(o.handle))
				return;
			src = itemOf(ev.target);
			ev.dataTransfer.effectAllowed = 'move';
			ev.dataTransfer.setData('text/plain', src.getAttribute(o.key));
			ev.dataTransfer.setDragImage(src, 16, 16);
			src.classList.add('mb-drag-src');
			src.addEventListener('dragend', end, { once: true });
		});
		list.addEventListener('dragover', function(ev) {
			var it = target(ev);
			if (!it)
				return;
			ev.preventDefault();
			clear();
			it.classList.add(follows(src, it) ? 'mb-drag-after' : 'mb-drag-before');
		});
		list.addEventListener('drop', function(ev) {
			var it = target(ev);
			if (!it)
				return;
			ev.preventDefault();
			var from = src.getAttribute(o.key);
			end();
			o.onDrop(from, it.getAttribute(o.key));
		});
	}
});
