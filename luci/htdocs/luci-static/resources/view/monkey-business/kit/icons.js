'use strict';
'require baseclass';

function svg(size, paths) {
	return '<svg viewBox="0 0 24 24" width="' + size + '" height="' + size + '" fill="none" stroke="currentColor" ' +
		'stroke-width="2" aria-hidden="true">' + paths + '</svg>';
}

return baseclass.extend({
	TRASH: svg(18, '<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"></path>'),
	EYE: svg(15, '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"></path><circle cx="12" cy="12" r="3"></circle>'),
	EYE_OFF: svg(15, '<path d="M3 3l18 18M10.6 5.1A10 10 0 0 1 12 5c6.5 0 10 7 10 7a17 17 0 0 1-3.2 4.1M6.1 6.1C3.4 7.9 2 12 2 12s3.5 7 10 7a9.6 9.6 0 0 0 5.9-2.1"></path>' +
		'<path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"></path>')
});
