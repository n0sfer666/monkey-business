'use strict';
'require view';
'require form';
'require rpc';
'require ui';
'require uci';
'require view.monkey-business.serverfields as fields';
'require view.monkey-business.serverlink as link';
'require view.monkey-business.subsection as subsection';
'require view.monkey-business.subs as subs';
'require view.monkey-business.commit as commit';

var callStatus = rpc.declare({ object: 'monkey-business', method: 'status' });
var callApply = rpc.declare({ object: 'monkey-business', method: 'config_apply' });

return view.extend({
	render: function() {
		var m = new form.Map('monkey-business', _('Servers'),
			_('Subscriptions (VPNON) and manual servers.'));

		subsection.create(m);

		var srv = m.section(form.GridSection, 'server', _('Manual servers'),
			_('Add servers by hand, or reorder fetched ones. Lower priority connects first; if unreachable, the next is used.'));
		srv.addremove = true;
		srv.anonymous = true;
		srv.sortable = true;
		srv.filter = function(sid) {
			var id = subs.serverSub(uci.get('monkey-business', sid));
			var known = uci.sections('monkey-business', 'subscription').map(function(s) { return s['.name']; });
			return id == null || known.length === 0 || known.indexOf(id) >= 0;
		};

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

		var subcol = srv.option(form.DummyValue, '_sub', _('Subscription'));
		subcol.cfgvalue = function(sid) {
			var id = subs.serverSub(uci.get('monkey-business', sid));
			return id ? (uci.get('monkey-business', id, 'name') || id) : _('manual');
		};

		var off = srv.option(form.Flag, 'disabled', _('Off'),
			_('Never used for connecting. Still listed and pinged.'));
		off.editable = true;

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
			return commit.apply();
		}).then(function() {
			return callStatus();
		}).then(function(st) {
			if (st && st.running)
				return callApply().then(function(res) {
					if (res && res.error)
						ui.addNotification(null, E('p', {}, [ _('Apply failed: ') + res.error ]), 'warning');
					else if (res && res.skipped == 'disabled')
						ui.addNotification(null, E('p', {}, [ _('Saved. The VPN is off — the new order will apply when you turn it on.') ]), 'info');
					else
						ui.addNotification(null, E('p', {}, [ _('Applied — connected to: ') + ((res && res.server) || '?') ]), 'info');
				});
			ui.addNotification(null, E('p', {}, [ _('Saved. Turn on to connect to the top-priority server.') ]), 'info');
		}).catch(function(e) {
			ui.addNotification(null, E('p', {}, [ _('Save & Apply failed: ') + e ]), 'error');
		});
	}
});
