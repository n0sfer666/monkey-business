'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.kit.tip as tip';
'require view.monkey-business.kit.icons as icons';

style.add('pingbar', [
	'.mb .mb-ping{display:flex;align-items:center;gap:8px;min-width:0;white-space:nowrap}',
	'.mb .mb-ping-bar{flex-shrink:0;width:56px;height:4px;border-radius:2px;overflow:hidden;background:var(--mb-line)}',
	'.mb .mb-ping-bar>div{height:100%;background:var(--mb-ok-text)}',
	'.mb .mb-ping-slow .mb-ping-bar>div{background:var(--mb-warn)}',
	'.mb .mb-ping-ms{font-family:var(--mb-mono)}',
	'.mb .mb-ping-fast .mb-ping-ms{color:var(--mb-ok-text)}',
	'.mb .mb-ping-slow .mb-ping-ms{color:var(--mb-slow)}',
	'.mb .mb-ping-off .mb-tip{color:var(--mb-err)}',
	'.mb .mb-ping-na .mb-tip{color:var(--mb-na)}',
	style.MOBILE + '{.mb .mb-ping-bar{display:none}.mb .mb-ping-ms{font-size:13px}.mb .mb-ping .mb-tip svg{width:18px;height:18px}}'
].join(''));

var LIMIT_MS = 1000;

function tipText(p) {
	if (p.kind === 'na')
		return _('hysteria2 runs over UDP: TCP ping does not apply, never auto-off');
	if (p.ms == null)
		return _('No reply to ping · auto-off until the next check');
	return _('%d ms, over the %d ms limit · auto-off').format(p.ms, LIMIT_MS);
}

function label(p) {
	if (p.kind === 'na')
		return _('n/a · UDP');
	if (p.kind === 'off')
		return _('auto-off');
	return p.ms != null ? p.ms + ' ms' : '—';
}

function flagged(p) {
	return tip.icon(tipText(p), p.kind === 'na' ? icons.NA : icons.WIFI_OFF);
}

return baseclass.extend({
	label: label,

	render: function(p) {
		var box = E('div', { 'class': 'mb-ping mb-ping-' + p.kind });
		if (p.kind === 'na' || p.kind === 'off')
			box.appendChild(flagged(p));
		else if (p.kind === 'none')
			box.appendChild(E('span', { 'class': 'mb-muted mb-mono' }, [ '—' ]));
		else
			box.appendChild(E('div', { 'class': 'mb-ping-bar' }, [ E('div', { 'style': 'width:' + p.pct + '%' }) ]));
		if (p.kind === 'fast' || p.kind === 'slow')
			box.appendChild(E('span', { 'class': 'mb-ping-ms' }, [ label(p) ]));
		return box;
	}
});
