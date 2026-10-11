'use strict';
'require baseclass';
'require view.monkey-business.kit.tokens as tokens';

var ID = 'mb-style';
var MOBILE = '@media (max-width: 720px)';
var STACK = '@media (max-width: 1000px)';
var added = {};

function vars(map) {
	return Object.keys(map).map(function(k) { return '--mb-' + k + ':' + map[k] + ';'; }).join('');
}

function theme() {
	return ':root{' + vars(tokens.light) + '}' +
		'@media (prefers-color-scheme: dark){:root:not([data-darkmode="false"]){' + vars(tokens.dark) + '}}' +
		':root[data-darkmode="true"]{' + vars(tokens.dark) + '}';
}

var CHEVRON = 'url("data:image/svg+xml,%3Csvg xmlns=\'http://www.w3.org/2000/svg\' viewBox=\'0 0 24 24\' ' +
	'fill=\'none\' stroke=\'%239ba1a8\' stroke-width=\'2\'%3E%3Cpath d=\'M6 9l6 6 6-6\'/%3E%3C/svg%3E")';

var BASE = [
	'.mb{--mb-mono:ui-monospace,"SF Mono",Menlo,monospace;font:13px/normal system-ui,-apple-system,"Segoe UI",sans-serif;color:var(--mb-text)}',
	'.mb *,.mb *::before,.mb *::after{box-sizing:border-box}',
	'.mb h1,.mb h2{margin:0;padding:0;border:0;font-weight:600;line-height:normal;color:var(--mb-text);background:none}',
	'.mb h1{font-size:20px}',
	'.mb h2{font-size:14px}',
	'.mb label{margin:0;padding:0;font-size:inherit;font-weight:inherit;color:inherit;cursor:inherit}',
	'.mb .mb-muted{color:var(--mb-muted)}',
	'.mb .mb-small{font-size:12px}',
	'.mb .mb-mono,.mb .mb-input.mb-mono{font-family:var(--mb-mono)}',
	'.mb .mb-panel{background:var(--mb-panel);border:1px solid var(--mb-line);border-radius:8px}',
	'.mb .mb-btn{display:inline-flex;align-items:center;justify-content:center;gap:6px;height:auto;margin:0;',
	'background:var(--mb-btn);color:var(--mb-text);border:1px solid var(--mb-line-strong);border-radius:6px;',
	'padding:6px 12px;font:inherit;line-height:normal;cursor:pointer;box-shadow:none;text-decoration:none}',
	'.mb .mb-btn:hover{border-color:var(--mb-line-strong)!important;box-shadow:none;filter:brightness(1.08)}',
	'.mb .mb-btn:disabled,.mb .mb-btn[aria-disabled="true"]{opacity:1;color:var(--mb-faint);border-color:var(--mb-line)!important;cursor:not-allowed;filter:none}',
	'.mb .mb-btn-primary{padding:6px 14px;background:var(--mb-primary);color:var(--mb-primary-text);font-weight:600}',
	'.mb .mb-btn-sm{padding:5px 10px}',
	'.mb .mb-btn-ico{display:inline-flex}',
	'.mb .mb-btn-primary,.mb .mb-btn-primary:hover{border-color:var(--mb-primary-edge)!important}',
	'.mb .mb-btn-tint{background:var(--mb-accent-tint);color:var(--mb-accent-text);font-weight:600}',
	'.mb .mb-btn-tint,.mb .mb-btn-tint:hover{border-color:var(--mb-accent-edge)!important}',
	'.mb .mb-btn-danger{background:var(--mb-err-tint);color:var(--mb-err-text);font-weight:600}',
	'.mb .mb-btn-danger,.mb .mb-btn-danger:hover{border-color:var(--mb-err-edge-strong)!important}',
	'.mb .mb-btn:disabled.mb-btn-primary,.mb .mb-btn-primary[aria-disabled="true"]{background:var(--mb-btn);border-color:var(--mb-line)!important}',
	'.mb .mb-link{margin:0;padding:0;background:transparent;color:var(--mb-link);border:0;font:inherit;line-height:normal;',
	'cursor:pointer;box-shadow:none;white-space:nowrap}',
	'.mb .mb-link:hover{color:var(--mb-link-hover);background:transparent;box-shadow:none}',
	'.mb .mb-link:disabled,.mb .mb-link[aria-disabled="true"]{color:var(--mb-faint);cursor:not-allowed}',
	'.mb .mb-icon{width:28px;height:28px;padding:0;background:transparent;color:var(--mb-muted);border-color:var(--mb-line)}',
	'.mb button:focus-visible{outline:2px solid var(--mb-accent);outline-offset:1px}',
	'.mb .mb-input{display:block;width:100%;min-width:0;max-width:none;height:auto;margin:0;',
	'background:var(--mb-bg);color:var(--mb-text);border:1px solid var(--mb-line-strong);border-radius:6px;',
	'padding:5px 8px;font:inherit;line-height:1.4;box-shadow:none}',
	'.mb .mb-input:focus{outline:none;border-color:var(--mb-accent)!important;box-shadow:none}',
	'.mb .mb-input::placeholder{color:var(--mb-faint)}',
	'.mb .mb-input.mb-bad,.mb .mb-input.mb-bad:focus{border-color:var(--mb-err)!important}',
	'.mb select.mb-input{appearance:none;-webkit-appearance:none;padding-right:30px;cursor:pointer;',
	'background:var(--mb-bg) ' + CHEVRON + ' no-repeat right 9px center/14px 14px}',
	'.mb .mb-check{appearance:auto;-webkit-appearance:auto;width:18px;height:18px;margin:0;flex-shrink:0;',
	'accent-color:var(--mb-accent);cursor:pointer;background:none;border:0;box-shadow:none}',
	'.mb .mb-check::before,.mb .mb-check::after{content:none;display:none}',
	'.mb .mb-check:focus{box-shadow:none}',
	'.mb .mb-check:focus-visible,.mb .mb-xbox:focus-visible{outline:2px solid var(--mb-accent);outline-offset:2px}',
	'.mb .mb-xbox{appearance:none;-webkit-appearance:none;display:grid;place-content:center;width:16px;height:16px;margin:0;flex-shrink:0;',
	'background:var(--mb-bg);border:1px solid var(--mb-check-edge);border-radius:4px;cursor:pointer;box-shadow:none}',
	'.mb .mb-xbox:focus{box-shadow:none;border-color:var(--mb-check-edge)!important}',
	'.mb .mb-xbox:disabled{cursor:not-allowed;opacity:.5}',
	'.mb .mb-xbox::before,.mb .mb-xbox::after{content:none;display:none}',
	'.mb .mb-xbox:checked,.mb .mb-xbox:checked:focus{background:var(--mb-warn);border-color:var(--mb-warn)!important}',
	'.mb .mb-xbox:checked::after{content:"\\2715";display:block;position:static;width:auto;height:auto;',
	'background:none;-webkit-mask:none;mask:none;color:var(--mb-on-warn);font:700 10px/1 system-ui,sans-serif}',
	MOBILE + '{',
	'.mb{font-size:14px}',
	'.mb .mb-btn{border-radius:8px;padding:10px 14px}',
	'.mb .mb-icon{width:36px;height:36px;padding:0}',
	'.mb .mb-input{border-radius:8px;padding:8px 10px}',
	'.mb select.mb-input{padding-right:34px}',
	'.mb .mb-check{width:22px;height:22px}',
	'}'
].join('');

function sheet() {
	var el = document.getElementById(ID);
	if (el)
		return el;
	el = E('style', { 'id': ID, 'type': 'text/css' }, [ theme() + BASE ]);
	document.head.appendChild(el);
	return el;
}

return baseclass.extend({
	MOBILE: MOBILE,
	STACK: STACK,

	add: function(name, css) {
		var el = sheet();
		if (added[name])
			return;
		added[name] = true;
		el.appendChild(document.createTextNode(css));
	}
});
