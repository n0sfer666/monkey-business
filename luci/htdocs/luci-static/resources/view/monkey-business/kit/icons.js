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
		'<path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"></path>'),
	GEAR: svg(18, '<circle cx="12" cy="12" r="3"></circle><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"></path>'),
	GRIP: svg(14, '<path d="M9 6h.01M15 6h.01M9 12h.01M15 12h.01M9 18h.01M15 18h.01" stroke-width="3" stroke-linecap="round"></path>'),
	MORE: svg(18, '<path d="M12 5h.01M12 12h.01M12 19h.01" stroke-width="3" stroke-linecap="round"></path>'),
	EDIT: svg(16, '<path d="M4 20h4L19 9l-4-4L4 16v4zM13 7l4 4"></path>'),
	ALERT: svg(14, '<circle cx="12" cy="12" r="9"></circle><path d="M12 7v6M12 16.5v.5"></path>'),
	SLASH: svg(14, '<circle cx="12" cy="12" r="9"></circle><path d="M6 18L18 6"></path>')
});
