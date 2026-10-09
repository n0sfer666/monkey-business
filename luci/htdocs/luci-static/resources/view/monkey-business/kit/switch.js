'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';

style.add('switch', [
	'.mb .mb-switch{position:relative;flex-shrink:0;width:44px;height:26px;margin:0;padding:0;border-radius:13px;cursor:pointer;',
	'background:var(--mb-line);border:1px solid var(--mb-line-strong);box-shadow:none}',
	'.mb .mb-switch:hover{border-color:var(--mb-line-strong)!important;box-shadow:none}',
	'.mb .mb-switch::after{content:"";position:absolute;top:2px;left:2px;width:20px;height:20px;border-radius:50%;',
	'background:var(--mb-muted);transition:left .15s}',
	'.mb .mb-switch[aria-checked="true"]{background:var(--mb-ok-fill)}',
	'.mb .mb-switch[aria-checked="true"],.mb .mb-switch[aria-checked="true"]:hover{border-color:var(--mb-ok)!important}',
	'.mb .mb-switch[aria-checked="true"]::after{left:20px;background:var(--mb-knob)}',
	'.mb .mb-switch:disabled{opacity:.5;cursor:not-allowed}'
].join(''));

return baseclass.extend({
	render: function(o) {
		var btn = E('button', {
			'type': 'button',
			'class': 'mb-switch',
			'role': 'switch',
			'id': o.id,
			'aria-checked': o.checked ? 'true' : 'false',
			'aria-label': o.label,
			'aria-labelledby': o.labelledby,
			'click': function() {
				var next = btn.getAttribute('aria-checked') !== 'true';
				btn.setAttribute('aria-checked', next ? 'true' : 'false');
				o.onChange(next);
			}
		});
		return btn;
	}
});
