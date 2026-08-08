'use strict';
'require baseclass';
'require rpc';
'require ui';
'require uci';
'require view.monkey-business.util as mbutil';

// Гео-базы: статус, фоновое обновление (дефолтный или свой URL), загрузка .dat с диска.
// Всё проходит валидацию через xray на устройстве — отсюда только UI и поллинг.
var callGeo = rpc.declare({ object: 'monkey-business', method: 'geo_update', params: ['geoip_url', 'geosite_url'] });
var callGeoStatus = rpc.declare({ object: 'monkey-business', method: 'geo_status' });
var callGeoInstall = rpc.declare({ object: 'monkey-business', method: 'geo_install', params: ['which'] });

function geoText(g) {
	if (!g) return _('unknown');
	var mb = function(b) { return b > 0 ? (b / 1048576).toFixed(1) + ' MB' : _('missing'); };
	// постоянный статус = размеры; «updating» при активном скачивании. Разовые ошибки — через нотификации.
	return 'geoip: ' + mb(g.geoip) + ', geosite: ' + mb(g.geosite) +
		(g.state === 'updating' ? ' — ' + _('updating…') : '');
}

function pollGeo() {
	var tries = 0;
	function step() {
		return callGeoStatus().then(function(g) {
			if (g.state !== 'updating' || ++tries >= 40) return g;
			return mbutil.sleep(2000).then(step);
		});
	}
	return step();
}

function updateMessage(g) {
	if (g.state === 'ok')
		return { msg: _('Geo databases updated & validated.'), kind: 'info' };
	if (g.state === 'unchanged')
		return { msg: _('Already up to date — nothing changed.'), kind: 'info' };
	return { msg: _('Geo update failed: ') + String(g.state || '').replace(/^error:\s*/, ''), kind: 'warning' };
}

return baseclass.extend({
	fetch: function() { return callGeoStatus(); },

	render: function(geo) {
		var self = this;
		var statusEl = E('span', {}, [ geoText(geo) ]);

		function refresh() { return callGeoStatus().then(function(g) { statusEl.textContent = geoText(g); }); }

		var urlGeoip = E('input', { 'type': 'text', 'style': 'width:100%;max-width:480px',
			'value': uci.get('monkey-business', 'geo', 'geoip_url') || '',
			'placeholder': _('custom geoip.dat URL (optional)') });
		var urlGeosite = E('input', { 'type': 'text', 'style': 'width:100%;max-width:480px',
			'value': uci.get('monkey-business', 'geo', 'geosite_url') || '',
			'placeholder': _('custom geosite.dat URL (optional)') });

		var updateBtn = E('button', { 'class': 'btn cbi-button cbi-button-apply',
			'click': ui.createHandlerFn(this, function() {
				return callGeo(urlGeoip.value || '', urlGeosite.value || '').then(function() {
						ui.showModal(_('Updating geo databases…'), [ E('p', { 'class': 'spinning' }, _('Downloading & validating (may take a minute)')) ]);
						return pollGeo().then(function(g) {
							ui.hideModal();
							statusEl.textContent = geoText(g);
							var r = updateMessage(g);
							ui.addNotification(null, E('p', r.msg), r.kind);
						});
					}).catch(function(e) {
						ui.hideModal();
						ui.addNotification(null, E('p', _('Geo update failed: ') + e), 'error');
					});
			})
		}, [ _('Update geo databases') ]);

		function uploader(which) {
			return E('button', { 'class': 'btn cbi-button',
				'click': ui.createHandlerFn(self, function() {
					return ui.uploadFile('/tmp/mb-upload-' + which + '.dat').then(function() {
						ui.showModal(_('Validating…'), [ E('p', { 'class': 'spinning' }, _('Checking ') + which + '.dat') ]);
						return callGeoInstall(which).then(function(res) {
							ui.hideModal();
							var ok = res && res.ok;
							ui.addNotification(null, E('p', ok ? (which + _('.dat installed & validated.')) : (_('Rejected: ') + ((res && res.detail) || ''))), ok ? 'info' : 'warning');
							return refresh();
						});
					}).catch(function(e) { ui.hideModal(); ui.addNotification(null, E('p', '' + e), 'error'); });
				})
			}, [ _('Upload ') + which + '.dat' ]);
		}

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ _('Geo databases') ]),
			E('p', {}, [ _('Current: '), statusEl ]),
			E('p', { 'style': 'color:#888' }, [ _('Download from default source or custom URLs, or upload .dat from disk. Files are validated with Xray before being installed.') ]),
			E('div', { 'style': 'display:flex;flex-direction:column;gap:6px;max-width:480px' }, [
				E('label', {}, [ _('Custom geoip URL') ]), urlGeoip,
				E('label', {}, [ _('Custom geosite URL') ]), urlGeosite
			]),
			E('p', { 'style': 'margin-top:8px' }, [ updateBtn, ' ', uploader('geoip'), ' ', uploader('geosite') ])
		]);
	}
});
