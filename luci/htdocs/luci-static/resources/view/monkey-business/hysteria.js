'use strict';
'require baseclass';
'require rpc';
'require ui';

// Клиент hysteria2 — отдельный бинарь: в feeds его нет, а 15МБ в ipk ради второго протокола дорого.
// Ставится кнопкой отсюда, тем же приёмом, что и geo-базы (фоновая закачка + поллинг статуса).
var callStatus = rpc.declare({ object: 'monkey-business', method: 'hysteria_status' });
var callInstall = rpc.declare({ object: 'monkey-business', method: 'hysteria_install' });

function sleep(ms) {
	return new Promise(function(r) { window.setTimeout(r, ms); });
}

function statusText(s) {
	if (!s || s.state === 'unsupported')
		return _('unknown');
	if (!s.installed)
		return (s.state === 'updating') ? _('installing…') : _('not installed');
	return _('installed') + (s.version ? ' (' + s.version + ')' : '') +
		(s.state === 'updating' ? ' — ' + _('updating…') : '');
}

function pollInstall() {
	var tries = 0;
	function step() {
		return callStatus().then(function(s) {
			if (!s || s.state !== 'updating' || ++tries >= 60) return s;
			return sleep(2000).then(step);
		});
	}
	return step();
}

return baseclass.extend({
	render: function(st) {
		var statusEl = E('span', {}, [ statusText(st) ]);

		var installBtn = E('button', {
			'class': 'btn cbi-button cbi-button-apply',
			'click': ui.createHandlerFn(this, function() {
				return callInstall().then(function(res) {
					if (res && res.error) {
						ui.addNotification(null, E('p', _('Install failed: ') + res.error), 'error');
						return;
					}
					ui.showModal(_('Installing hysteria…'), [
						E('p', { 'class': 'spinning' }, _('Downloading & checking the client (may take a minute)'))
					]);
					return pollInstall().then(function(s) {
						ui.hideModal();
						statusEl.textContent = statusText(s);
						var ok = s && s.installed && s.state !== 'updating';
						ui.addNotification(null, E('p', ok
							? _('hysteria client installed.')
							: _('Install failed: ') + String((s && s.state) || '').replace(/^error:\s*/, '')),
							ok ? 'info' : 'warning');
					});
				}).catch(function(e) {
					ui.hideModal();
					ui.addNotification(null, E('p', _('Install failed: ') + e), 'error');
				});
			})
		}, [ _('Install / update hysteria') ]);

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ _('hysteria2 client') ]),
			E('p', {}, [ _('Current: '), statusEl ]),
			E('p', { 'style': 'color:#888' }, [
				_('Needed only for hysteria2:// servers in your subscription — VLESS/Reality works without it. The client runs next to Xray and the split rules stay the same.')
			]),
			E('p', {}, [ installBtn ])
		]);
	}
});
