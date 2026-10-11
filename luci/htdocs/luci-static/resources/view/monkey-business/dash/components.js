'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.kit.guard as guard';
'require view.monkey-business.dash.geoalert as geoalert';
'require view.monkey-business.dash.hyinstall as hyinstall';

style.add('dash-components', [
	'.mb .mb-dash-comps{display:flex;flex-direction:column;padding:6px 14px}',
	'.mb .mb-dash-comps h2{margin:6px 0 4px}',
	'.mb .mb-dash-comp{display:flex;align-items:center;gap:10px;padding:8px 0;border-top:1px solid var(--mb-line)}',
	'.mb .mb-dash-comp>div{display:flex;align-items:center;gap:10px;flex-grow:1;min-width:0}',
	'.mb .mb-dash-comp>div>span:first-child{flex-shrink:0;width:84px;color:var(--mb-muted)}',
	'.mb .mb-dash-word{font-weight:500}',
	'.mb .mb-dash-word-ok{color:var(--mb-ok-text)}',
	'.mb .mb-dash-word-err{color:var(--mb-err-text)}',
	style.MOBILE + '{',
	'.mb .mb-dash-comps{padding:4px 14px;border-radius:10px}',
	'.mb .mb-dash-comps h2{display:none}',
	'.mb .mb-dash-comp{padding:10px 0}',
	'.mb .mb-dash-comps h2+.mb-dash-comp{border-top:0}',
	'.mb .mb-dash-comp>div{flex-direction:column;align-items:flex-start;gap:2px}',
	'.mb .mb-dash-comp>div>span:first-child{width:auto;color:var(--mb-text)}',
	'.mb .mb-dash-comp>div>span:last-child{color:var(--mb-muted);font-size:12px}',
	'.mb .mb-dash-comp .mb-link{padding:8px 0}',
	'}'
].join(''));

function mb(bytes) {
	return (bytes / 1048576).toFixed(1) + '\u00a0MB';
}

function geoState(g) {
	if (!g || g.geoip == null)
		return { word: _('unknown'), cls: '', detail: '' };
	if (geoalert.missing(g))
		return { word: _('missing'), cls: 'err', detail: ' · ' + _('%s not found').format(geoalert.missingText(g)) };
	return { word: _('installed'), cls: 'ok', detail: ' · geoip\u00a0' + mb(g.geoip) + ' · geosite\u00a0' + mb(g.geosite) +
		(g.state === 'updating' ? ' · ' + _('updating…') : '') };
}

function hyState(h) {
	if (!h || h.state === 'unsupported')
		return null;
	if (h.state === 'updating')
		return { word: h.installed ? _('updating…') : _('installing…'), cls: '', detail: '', action: _('Update') };
	if (!h.installed)
		return { word: _('not installed'), cls: '', detail: '', action: _('Install') };
	return { word: _('installed'), cls: 'ok', detail: h.version ? ' · ' + h.version : '', action: _('Update') };
}

function row(name, link) {
	var word = E('span', { 'class': 'mb-dash-word' });
	var detail = E('span');
	var node = E('div', { 'class': 'mb-dash-comp' }, [
		E('div', {}, [ E('span', {}, [ name ]), E('span', {}, [ word, detail ]) ]),
		link
	]);
	return {
		node: node,
		paint: function(s) {
			node.hidden = !s;
			if (!s)
				return;
			word.className = 'mb-dash-word' + (s.cls ? ' mb-dash-word-' + s.cls : '');
			word.textContent = s.word;
			detail.textContent = s.detail;
			if (s.action)
				link.textContent = s.action;
		}
	};
}

return baseclass.extend({
	render: function(o) {
		var geoLink = E('button', { 'type': 'button', 'class': 'mb-link', 'aria-haspopup': 'dialog', 'disabled': o.readonly ? '' : null, 'click': o.onGeo }, [ _('Update…') ]);
		var hyLink = E('button', { 'type': 'button', 'class': 'mb-link', 'disabled': o.readonly ? '' : null });
		var geo = row(_('geo data'), geoLink);
		var hy = row('hysteria2', hyLink);
		var last = null;

		function showHy(h) {
			last = h;
			hy.paint(hyState(h));
		}

		function track(job) {
			guard.run(hyLink, job).then(function(s) {
				if (s)
					showHy(s);
			});
		}

		function installing() {
			hy.paint(hyState({ installed: !!(last && last.installed), state: 'updating' }));
		}

		hyLink.addEventListener('click', function() {
			track(function() { return hyinstall.run(installing); });
		});

		return {
			node: E('section', { 'class': 'mb-panel mb-dash-comps', 'aria-label': _('Components') }, [
				E('h2', {}, [ _('Components') ]), geo.node, hy.node
			]),
			geo: function(g) { geo.paint(geoState(g)); },
			hysteria: function(h) {
				showHy(h);
				if (h && h.state === 'updating')
					track(hyinstall.watch);
			}
		};
	}
});
