'use strict';
'require baseclass';
'require rpc';
'require ui';
'require poll';
'require view.monkey-business.util as mbutil';

// Секция «Status»: живая метка состояния, тумблер и проверка точки выхода.
var callStatus = rpc.declare({ object: 'monkey-business', method: 'status' });
var callCheckExit = rpc.declare({ object: 'monkey-business', method: 'check_exit', params: ['domain'] });
var callToggle = rpc.declare({ object: 'monkey-business', method: 'service_toggle', params: ['enabled'] });

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

function pollUntilRunning() {
	var tries = 0;
	function step() {
		return callStatus().then(function(st) {
			if (st.running) return true;
			if (++tries >= 12) return false;
			return mbutil.sleep(1500).then(step);
		});
	}
	return step();
}

// Turn on реально подключает: ждём running и показываем ошибку вместо бесконечного «Starting…».
function handleToggle(on) {
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
		return pollUntilRunning().then(function(ok) {
			ui.hideModal();
			if (!ok)
				ui.addNotification(null, E('p', _('Service did not come up — check logs (logread | grep xray).')), 'warning');
			window.location.reload();
		});
	}).catch(function(e) {
		ui.hideModal();
		ui.addNotification(null, E('p', _('Connect error: ') + e), 'error');
	});
}

function exitCheck(self) {
	var exitEl = E('span', { 'style': 'font-family:monospace' }, [ '—' ]);
	var btn = E('button', {
		'class': 'btn cbi-button',
		'click': ui.createHandlerFn(self, function() {
			exitEl.textContent = _('checking…');
			return callCheckExit('').then(function(r) {
				if (r && r.error) exitEl.textContent = r.error;
				else exitEl.textContent = (r.ip || '?') + ' — ' + (r.country || '?') + ' (' + (r.code || '?') + ')';
			}).catch(function(e) { exitEl.textContent = '' + e; });
		})
	}, [ _('Check exit IP') ]);
	return E('p', { 'style': 'margin-top:10px' }, [
		btn, ' ', E('span', {}, [ _('Exit (via VPN routing): ') ]), exitEl,
		E('br'), E('small', { 'style': 'color:#888' }, [ _('Probes ip-api.com through the split rules. Add it to the Direct list above to see your real IP instead.') ])
	]);
}

return baseclass.extend({
	// Дашборд берёт стартовый снимок отсюда же, чтобы rpc.declare('status') жил в одном месте.
	fetch: function() { return callStatus(); },

	render: function(st) {
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
			'click': ui.createHandlerFn(this, function() { return handleToggle(!toggleOn); })
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

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ _('Status') ]),
			labelEl,
			noteEl,
			serverEl,
			routingEl,
			toggleEl,
			exitCheck(this)
		]);
	}
});
