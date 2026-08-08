'use strict';
'require view';
'require form';
'require rpc';
'require ui';
'require uci';
'require view.monkey-business.serverfields as fields';
'require view.monkey-business.serverlink as link';

var callSubUpdate = rpc.declare({
	object: 'monkey-business', method: 'subscription_update', params: ['url']
});
var callStatus = rpc.declare({ object: 'monkey-business', method: 'status' });
var callApply = rpc.declare({ object: 'monkey-business', method: 'config_apply' });

function notifyResult(res) {
	if (res && res.error)
		ui.addNotification(null, E('p', _('Subscription update failed: ') + res.error), 'warning');
	else
		ui.addNotification(null, E('p', _('Servers fetched: ') + ((res && res.added) || 0)), 'info');
	return res;
}

return view.extend({
	render: function() {
		var m = new form.Map('monkey-business', _('Servers'),
			_('Subscription (VPNON) and manual servers.'));

		var sub = m.section(form.NamedSection, 'subscription', 'subscription',
			_('Subscription'));

		var url = sub.option(form.Value, 'url', _('Subscription URL'),
			_('VPNON subscription link. Type it and press "Fetch subscription" — it is saved automatically when the fetch succeeds.'));
		url.password = true;

		var auto = sub.option(form.Flag, 'auto_update', _('Auto-update'),
			_('Refresh the server list on a schedule.'));
		auto.default = '1';
		// rmempty=false обязателен: значение, совпавшее с default, LuCI удаляет из UCI на каждом
		// Save формы — и subupdate.sh читал бы пустоту вместо выбора пользователя.
		auto.rmempty = false;

		var interval = sub.option(form.Value, 'update_interval', _('Interval (sec)'),
			_('How often to refresh the subscription. Values below 300 are clamped to 300.'));
		interval.depends('auto_update', '1');
		interval.datatype = 'uinteger';
		interval.default = '86400';
		interval.rmempty = false;
		// Выключенное автообновление прячет поле; без retain Save стёр бы заданный интервал,
		// и обратное включение молча вернуло бы сутки.
		interval.retain = true;

		var btn = sub.option(form.Button, '_update', _('Update now'));
		btn.inputtitle = _('Fetch subscription');
		btn.inputstyle = 'apply';
		btn.onclick = function() {
			var typed = url.formvalue('subscription') || '';
			if (typed === '') {
				ui.addNotification(null, E('p', _('Enter a subscription URL first.')), 'warning');
				return Promise.resolve();
			}
			ui.showModal(_('Fetching subscription…'), [ E('p', { 'class': 'spinning' }, _('Contacting server')) ]);
			return callSubUpdate(typed).then(function(res) {
				ui.hideModal();
				notifyResult(res);
				if (!(res && res.error))
					window.setTimeout(function() { window.location.reload(); }, 600);
			}).catch(function(e) {
				ui.hideModal();
				ui.addNotification(null, E('p', _('Fetch error: ') + e), 'error');
			});
		};

		var srv = m.section(form.GridSection, 'server', _('Manual servers'),
			_('Add servers by hand, or reorder fetched ones. Lower priority connects first; if unreachable, the next is used.'));
		srv.addremove = true;
		srv.anonymous = true;
		srv.sortable = true;

		// Порядок в модалке: переключатель -> ссылка -> сами поля. Разобранная ссылка раскрывается
		// в те же поля, поэтому перед сохранением её видно и можно поправить.
		fields.mode(srv);
		link.create(srv, function(section, section_id, flat) {
			var show = section.getOption('_show');
			var el = show ? show.getUIElement(section_id) : null;
			if (el != null)
				el.setValue('1');
			fields.fill(section, section_id, flat);
		});
		fields.create(srv);

		// Клик по Save снимает фокус со ссылки и только ЗАПУСКАЕТ разбор на устройстве — ответ
		// придёт позже самого сохранения. Без ожидания секция сохранилась бы с пустыми полями:
		// «Name must not be empty» на ровном месте и второй Save, чтобы всё получилось.
		srv.handleModalSave = function() {
			var self = this, args = arguments;
			var save = function() {
				return form.GridSection.prototype.handleModalSave.apply(self, args);
			};
			var wait = link.pending();
			return wait ? wait.then(save, save) : save();
		};

		return m.render().then(function(node) {
			node.appendChild(E('style', { 'type': 'text/css' },
				'#cbi-monkey-business-server .cbi-section-table-titles > * {' +
				' position: sticky; top: 0; z-index: 2;' +
				' background: var(--background-color-medium, var(--background-color, #2b2b2b)); }'));

			function wrapTable() {
				var sec = node.querySelector('#cbi-monkey-business-server');
				if (!sec) return;
				var tbl = sec.querySelector(':scope > table.cbi-section-table');
				if (!tbl) return;
				var wrap = E('div', { 'class': 'mb-scroll', 'style': 'max-height:55vh;overflow-y:auto' });
				tbl.parentNode.insertBefore(wrap, tbl);
				wrap.appendChild(tbl);
			}

			wrapTable();
			var sec = node.querySelector('#cbi-monkey-business-server');
			if (sec)
				new MutationObserver(wrapTable).observe(sec, { childList: true });
			return node;
		});
	},

	// Save & Apply: commit формы (порядок/серверы/URL), и если VPN включён — переприменить конфиг,
	// чтобы переключиться на новый первый-по-приоритету сервер. handleSave без apply раньше оставлял
	// изменения в "Unsaved Changes".
	handleSaveApply: function(ev, mode) {
		return this.handleSave(ev).then(function() {
			return uci.apply();
		}).then(function() {
			return callStatus();
		}).then(function(st) {
			if (st && st.running)
				return callApply().then(function(res) {
					if (res && res.error)
						ui.addNotification(null, E('p', _('Apply failed: ') + res.error), 'warning');
					else if (res && res.skipped == 'disabled')
						ui.addNotification(null, E('p', _('Saved. The VPN is off — the new order will apply when you turn it on.')), 'info');
					else
						ui.addNotification(null, E('p', _('Applied — connected to: ') + ((res && res.server) || '?')), 'info');
				});
			ui.addNotification(null, E('p', _('Saved. Turn on to connect to the top-priority server.')), 'info');
		}).catch(function(e) {
			ui.addNotification(null, E('p', _('Save & Apply failed: ') + e), 'error');
		});
	}
});
