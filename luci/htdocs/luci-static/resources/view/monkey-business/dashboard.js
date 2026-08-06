'use strict';
'require view';
'require rpc';
'require ui';
'require uci';
'require poll';
'require view.monkey-business.routing as mbroute';
'require view.monkey-business.hysteria as mbhy';

var callStatus = rpc.declare({ object: 'monkey-business', method: 'status' });
var callServers = rpc.declare({ object: 'monkey-business', method: 'servers_list' });
var callPing = rpc.declare({ object: 'monkey-business', method: 'servers_ping' });
var callGeo = rpc.declare({ object: 'monkey-business', method: 'geo_update', params: ['geoip_url', 'geosite_url'] });
var callSetRouting = rpc.declare({ object: 'monkey-business', method: 'set_routing', params: ['direct', 'proxy'] });
var callGeoStatus = rpc.declare({ object: 'monkey-business', method: 'geo_status' });
var callHyStatus = rpc.declare({ object: 'monkey-business', method: 'hysteria_status' });
var callGeoInstall = rpc.declare({ object: 'monkey-business', method: 'geo_install', params: ['which'] });
var callCheckExit = rpc.declare({ object: 'monkey-business', method: 'check_exit', params: ['domain'] });
var callToggle = rpc.declare({
	object: 'monkey-business', method: 'service_toggle', params: ['enabled']
});

function toGB(bytes) {
	var n = parseFloat(bytes);
	if (isNaN(n) || n <= 0) return 0;
	return n / 1073741824;
}

function fmtDate(epoch) {
	var n = parseInt(epoch, 10);
	if (isNaN(n) || n <= 0) return '-';
	return new Date(n * 1000).toISOString().slice(0, 10);
}

function sleep(ms) {
	return new Promise(function(r) { window.setTimeout(r, ms); });
}

// Раньше «выключено» и «watchdog снял туннель, LAN идёт напрямую» выглядели одинаково —
// как «Starting…», то есть «сейчас поднимется». Фаза watchdog из status делает разницу видимой.
// Живой процесс приоритетнее фазы: файл состояния watchdog обновляется раз в минуту, и по нему
// нельзя объявлять «трафик идёт мимо VPN», когда xray уже поднят — ложное обещание в обе стороны
// опаснее задержки в минуту.
function phaseInfo(st) {
	// Тумблер выключен, а туннель поднят — состояние достижимо (несохранившееся намерение, ручной
	// reload с MB_INTENT). Печатать «Off» тут значит врать наоборот: весь LAN идёт в туннель, а
	// kill-switch армирован, и никто за этим не следит — watchdog смотрит на UCI.
	if (!st.enabled && st.running)
		return {
			label: _('Off — tunnel still up'), color: '#ff7f00', tint: 'rgba(255,127,0,.08)',
			note: _('The toggle is off, but xray and the kill-switch are still up. Press Turn on to finish enabling, then Turn off to tear it down.')
		};
	if (!st.enabled)
		return { label: _('Off'), color: '#888', note: '', tint: '' };
	if (st.running)
		return { label: _('Connected'), color: '#33a02c', note: '', tint: '' };
	if (st.wd_phase === 'down')
		return {
			label: _('Disabled by watchdog'), color: '#e31a1c', tint: 'rgba(227,26,28,.08)',
			note: _('No working server found — traffic goes directly, WITHOUT VPN.')
		};
	if (st.wd_phase === 'reconnecting')
		return {
			label: _('Reconnecting…'), color: '#ff7f00', tint: 'rgba(255,127,0,.08)',
			note: _('The tunnel dropped, the watchdog is reconnecting. Kill-switch is still held.')
		};
	return { label: _('Starting…'), color: '#ff7f00', note: '', tint: '' };
}

// Ядерный обход — производная режима, а не отдельная настройка: по одной строке «Routing: gfwlist»
// не понять, ходит ли ещё часть трафика мимо xray. Поллится вместе со статусом, поэтому смена
// режима видна тут же, без перезагрузки страницы.
function routingText(st) {
	return _('Routing: ') + (st.routing_mode || '-') + (st.direct_bypass ? _(' + kernel bypass') : '');
}

return view.extend({
	load: function() {
		// каждый вызов с фолбэком: один упавший ubus-метод не должен ронять всю вьюшку
		return Promise.all([
			callStatus().catch(function() { return {}; }),
			callServers().catch(function() { return {}; }),
			uci.load('monkey-business').catch(function() { return null; }),
			callGeoStatus().catch(function() { return {}; }),
			callHyStatus().catch(function() { return {}; })
		]);
	},

	geoText: function(g) {
		if (!g) return _('unknown');
		var mb = function(b) { return b > 0 ? (b / 1048576).toFixed(1) + ' MB' : _('missing'); };
		// постоянный статус = размеры; «updating» при активном скачивании. Разовые ошибки — через нотификации.
		return 'geoip: ' + mb(g.geoip) + ', geosite: ' + mb(g.geosite) +
			(g.state === 'updating' ? ' — ' + _('updating…') : '');
	},

	pollGeo: function() {
		var tries = 0;
		function step() {
			return callGeoStatus().then(function(g) {
				if (g.state !== 'updating' || ++tries >= 40) return g;
				return sleep(2000).then(step);
			});
		}
		return step();
	},

	// #6 — traffic readout (only if subscription reported it)
	renderTraffic: function(t) {
		if (!t || !t.total || toGB(t.total) <= 0)
			return E([]);
		var used = toGB(t.used_download) + toGB(t.used_upload);
		var total = toGB(t.total);
		var pct = total > 0 ? Math.min(100, Math.round(used / total * 100)) : 0;
		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ _('Subscription traffic') ]),
			E('p', {}, [ used.toFixed(1) + ' / ' + total.toFixed(1) + ' GB (' + pct + '%)' ]),
			E('div', { 'style': 'background:#ddd;border-radius:4px;height:14px;width:100%;max-width:420px;overflow:hidden' }, [
				E('div', { 'style': 'background:' + (pct < 90 ? '#33a02c' : '#e31a1c') + ';height:14px;width:' + pct + '%' }, [])
			]),
			E('p', { 'style': 'color:#888' }, [ _('Expires: ') + fmtDate(t.expire) ])
		]);
	},

	pollUntilRunning: function() {
		var tries = 0;
		function step() {
			return callStatus().then(function(st) {
				if (st.running) return true;
				if (++tries >= 12) return false;
				return sleep(1500).then(step);
			});
		}
		return step();
	},

	// #2 — Turn on actually connects; poll for running; surface errors instead of endless "Starting…"
	handleToggle: function(on) {
		var self = this;
		if (!on)
			return callToggle(false).then(function() { window.location.reload(); }).catch(function(e) {
				ui.addNotification(null, E('p', _('Turn off failed: ') + e), 'error');
			});

		ui.showModal(_('Connecting…'), [ E('p', { 'class': 'spinning' }, _('Selecting server and starting Xray')) ]);
		return callToggle(true).then(function(res) {
			if (res && res.error) {
				ui.hideModal();
				ui.addNotification(null, E('p', _('Connect failed: ') + res.error), 'error');
				return;
			}
			return self.pollUntilRunning().then(function(ok) {
				ui.hideModal();
				if (!ok)
					ui.addNotification(null, E('p', _('Service did not come up — check logs (logread | grep xray).')), 'warning');
				window.location.reload();
			});
		}).catch(function(e) {
			ui.hideModal();
			ui.addNotification(null, E('p', _('Connect error: ') + e), 'error');
		});
	},

	renderStatus: function(st) {
		var self = this;
		var on = !!st.enabled;
		var toggleOn = on;
		var info = phaseInfo(st);

		var labelEl = E('p', { 'style': 'font-size:1.4em;color:' + info.color }, [ info.label ]);
		var serverEl = E('p', {}, [ _('Server: ') + (st.server || _('none')) ]);
		var noteEl = E('div', {
			'style': 'display:' + (info.note ? 'block' : 'none') +
				';margin:8px 0;padding:8px 12px;border-left:4px solid ' + info.color + ';background:' + info.tint
		}, [ E('strong', {}, [ info.note ]), E('br'), E('small', { 'style': 'font-family:monospace;color:#888' }, [ st.last_event || '' ]) ]);

		var routingEl = E('p', {}, [ routingText(st) ]);
		var toggleEl = E('button', {
			'class': 'btn cbi-button ' + (on ? 'cbi-button-remove' : 'cbi-button-apply'),
			'click': ui.createHandlerFn(this, function() { return self.handleToggle(!toggleOn); })
		}, [ on ? _('Turn off') : _('Turn on') ]);

		// Вьюшка не поллилась вовсе: страница показывала снимок момента загрузки, поэтому переход
		// в down пользователь замечал только вручную перезагрузив LuCI.
		poll.add(function() {
			return callStatus().then(function(cur) {
				var next = phaseInfo(cur);
				labelEl.textContent = next.label;
				labelEl.style.color = next.color;
				serverEl.textContent = _('Server: ') + (cur.server || _('none'));
				routingEl.textContent = routingText(cur);
				noteEl.style.display = next.note ? 'block' : 'none';
				noteEl.style.borderLeftColor = next.color;
				noteEl.style.background = next.tint;
				noteEl.firstChild.textContent = next.note;
				noteEl.lastChild.textContent = cur.last_event || '';
				// Кнопка тоже живая: иначе после автоотключения она предлагала бы «Turn off»
				// на уже выключенном сервисе.
				toggleOn = !!cur.enabled;
				toggleEl.textContent = toggleOn ? _('Turn off') : _('Turn on');
				toggleEl.className = 'btn cbi-button ' + (toggleOn ? 'cbi-button-remove' : 'cbi-button-apply');
				labelEl.style.opacity = '1';
			}).catch(function() {
				// Молчаливый catch выдавал бы устаревший снимок за актуальный статус —
				// приглушаем метку, чтобы отказ ubus был виден.
				labelEl.style.opacity = '.4';
			});
		}, 5);

		var exitEl = E('span', { 'style': 'font-family:monospace' }, [ '—' ]);
		var checkBtn = E('button', {
			'class': 'btn cbi-button',
			'click': ui.createHandlerFn(this, function() {
				exitEl.textContent = _('checking…');
				return callCheckExit('').then(function(r) {
					if (r && r.error) exitEl.textContent = r.error;
					else exitEl.textContent = (r.ip || '?') + ' — ' + (r.country || '?') + ' (' + (r.code || '?') + ')';
				}).catch(function(e) { exitEl.textContent = '' + e; });
			})
		}, [ _('Check exit IP') ]);

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ _('Status') ]),
			labelEl,
			noteEl,
			serverEl,
			routingEl,
			toggleEl,
			E('p', { 'style': 'margin-top:10px' }, [
				checkBtn, ' ', E('span', {}, [ _('Exit (via VPN routing): ') ]), exitEl,
				E('br'), E('small', { 'style': 'color:#888' }, [ _('Probes ip-api.com through the split rules. Add it to the Direct list above to see your real IP instead.') ])
			])
		]);
	},

	// #5 — custom direct/vpn lists (split-tunnel only) + geo databases
	renderRouting: function() {
		var self = this;
		var direct = uci.get('monkey-business', 'global', 'custom_direct') || '';
		var proxy = uci.get('monkey-business', 'global', 'custom_proxy') || '';

		var taDirect = E('textarea', {
			'rows': 6, 'style': 'width:100%;max-width:480px',
			'placeholder': 'example.com\n*.frontier.com\n10.0.0.0/8\ngeosite:category-ru\ngeoip:ru'
		}, [ direct ]);
		var taProxy = E('textarea', {
			'rows': 6, 'style': 'width:100%;max-width:480px',
			'placeholder': 'blocked.example\n*.netflix.com\ngeosite:google\ngeoip:netflix'
		}, [ proxy ]);

		var save = E('button', {
			'class': 'btn cbi-button cbi-button-apply',
			'click': ui.createHandlerFn(this, function() {
				// серверный commit+apply (без LuCI-стейджинга, иначе остаётся в Unsaved Changes)
				return callSetRouting(taDirect.value, taProxy.value).then(function(res) {
					if (res && res.error)
						ui.addNotification(null, E('p', _('Apply failed: ') + res.error), 'warning');
					else if (res && res.skipped == 'disabled')
						ui.addNotification(null, E('p', _('Rules saved. The VPN is off — they will apply when you turn it on.')), 'info');
					else
						ui.addNotification(null, E('p', _('Routing rules applied.')), 'info');
				});
			})
		}, [ _('Save & Apply') ]);

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ _('Custom routing (split-tunnel)') ]),
			E('p', { 'style': 'color:#888' }, [ _('One entry per line: domain, *.domain (matches the domain and all subdomains), IP/CIDR, geosite:NAME or geoip:NAME. Active only in split-tunnel modes (not "Everything via VPN").') ]),
			E('div', { 'style': 'display:flex;gap:24px;flex-wrap:wrap' }, [
				E('div', {}, [ E('strong', {}, [ _('Direct (bypass VPN)') ]), taDirect ]),
				E('div', {}, [ E('strong', {}, [ _('Via VPN') ]), taProxy ])
			]),
			E('p', { 'style': 'margin-top:8px' }, [ save ])
		]);
	},

	// Geo databases: status, background update (default or custom URL), upload from disk — all validated.
	renderGeo: function(geo) {
		var self = this;
		var statusEl = E('span', {}, [ this.geoText(geo) ]);

		function refresh() { return callGeoStatus().then(function(g) { statusEl.textContent = self.geoText(g); }); }

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
						return self.pollGeo().then(function(g) {
							ui.hideModal();
							statusEl.textContent = self.geoText(g);
							var msg, kind;
							if (g.state === 'ok') { msg = _('Geo databases updated & validated.'); kind = 'info'; }
							else if (g.state === 'unchanged') { msg = _('Already up to date — nothing changed.'); kind = 'info'; }
							else { msg = _('Geo update failed: ') + String(g.state || '').replace(/^error:\s*/, ''); kind = 'warning'; }
							ui.addNotification(null, E('p', msg), kind);
						});
					}).catch(function(e) {
						ui.hideModal();
						ui.addNotification(null, E('p', _('Geo update failed: ') + e), 'error');
					});
			})
		}, [ _('Update geo databases') ]);

		function uploader(which) {
			return E('button', { 'class': 'btn cbi-button',
				'click': ui.createHandlerFn(this, function() {
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
	},

	renderServers: function(servers) {
		// tag приходит из подписки (внешний источник) -> не строим CSS-селектор по нему.
		// Держим ссылки на ping-ячейки в map по tag и обновляем напрямую.
		var pingCells = {};
		var rows = (servers || []).map(function(s) {
			var pingTd = E('td', { 'class': 'td' }, [ '—' ]);
			pingCells[s.tag] = pingTd;
			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td' }, [ '' + (s.priority != null ? s.priority : '-') ]),
				E('td', { 'class': 'td' }, [ s.tag ]),
				E('td', { 'class': 'td' }, [ s.address + ':' + s.port ]),
				// insecure=1 из подписки отключает проверку сертификата — это обязано быть видно:
				// иначе такой сервер выглядит ровно как проверяемый.
				E('td', { 'class': 'td' }, [ (s.protocol || 'vless') + ' / ' + s.security +
					(s.insecure ? _(' (insecure)') : '') ]),
				pingTd
			]);
		});

		var table = E('table', { 'class': 'table' }, [
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, [ _('Prio') ]),
				E('th', { 'class': 'th' }, [ _('Name') ]),
				E('th', { 'class': 'th' }, [ _('Address') ]),
				E('th', { 'class': 'th' }, [ _('Protocol / security') ]),
				E('th', { 'class': 'th' }, [ _('Ping') ])
			])
		].concat(rows));

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ _('Servers') ]),
			E('button', {
				'class': 'btn cbi-button',
				'click': ui.createHandlerFn(this, function() {
					return callPing().then(function(res) {
						(res.results || []).forEach(function(r) {
							var cell = pingCells[r.tag];
							if (cell)
								cell.textContent = (r.latency_ms != null) ? (r.latency_ms + ' ms') : _('down');
						});
					}).catch(function(e) {
						ui.addNotification(null, E('p', _('Latency test failed: ') + e), 'error');
					});
				})
			}, [ _('Test latency') ]),
			table
		]);
	},

	render: function(data) {
		var st = data[0] || {};
		var servers = (data[1] || {}).servers || [];
		var geo = data[3] || {};
		return E('div', {}, [
			this.renderTraffic(st.traffic),
			this.renderStatus(st),
			mbroute.render(),
			this.renderRouting(),
			this.renderGeo(geo),
			mbhy.render(data[4] || {}),
			this.renderServers(servers)
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
