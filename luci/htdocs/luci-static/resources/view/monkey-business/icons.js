'use strict';
'require baseclass';

var SVG = {
	ping: '<svg viewBox="0 0 24 24" width="1em" height="1em" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="square" aria-hidden="true">' +
		'<polyline points="21 14 18 14 15 7 10 17 7 11 5 14 3 14"/></svg>',
	alert: '<svg viewBox="0 0 24 24" width="1em" height="1em" fill="none" aria-hidden="true">' +
		'<path fill-rule="evenodd" clip-rule="evenodd" fill="currentColor" d="M9.82664 2.22902C10.7938 0.590326 13.2063 0.590325 14.1735 2.22902L23.6599 18.3024C24.6578 19.9933 23.3638 22 21.4865 22H2.51362C0.63634 22 -0.657696 19.9933 0.340215 18.3024L9.82664 2.22902ZM10.0586 7.05547C10.0268 6.48227 10.483 6 11.0571 6H12.9429C13.517 6 13.9732 6.48227 13.9414 7.05547L13.5525 14.0555C13.523 14.5854 13.0847 15 12.554 15H11.446C10.9153 15 10.477 14.5854 10.4475 14.0555L10.0586 7.05547ZM14 18C14 19.1046 13.1046 20 12 20C10.8954 20 10 19.1046 10 18C10 16.8954 10.8954 16 12 16C13.1046 16 14 16.8954 14 18Z"/></svg>'
};

function icon(name) {
	return E('span', { 'style': 'display:inline-block;vertical-align:-0.125em;line-height:0' }, SVG[name]);
}

return baseclass.extend({
	icon: icon,

	button: function(name, label, handler, hint) {
		return E('button', {
			'class': 'btn cbi-button',
			'title': hint || label,
			'click': handler
		}, [ icon(name), label ? ' ' + label : '' ]);
	}
});
