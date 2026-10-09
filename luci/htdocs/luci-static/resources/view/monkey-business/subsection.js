'use strict';
'require baseclass';
'require form';
'require view.monkey-business.api as api';
'require ui';
'require view.monkey-business.store as store';
'require view.monkey-business.subs as subs';
'require view.monkey-business.icons as icons';

var CONFIG = 'monkey-business';
var UNKNOWN_SUB = 'unknown subscription';

function notify(text, level) {
	ui.addNotification(null, E('p', {}, [ text ]), level);
}

function notifyFetch(res) {
	if (res && res.error)
		notify(_('Subscription update failed: ') + res.error, 'warning');
	else
		notify(_('Servers fetched: ') + ((res && res.added) || 0), 'info');
}

function notifyPing(res) {
	if (res && res.error)
		return notify(_('Ping failed: ') + res.error, 'warning');
	var results = (res && res.results) || [];
	var count = function(pred) { return results.filter(pred).length; };
	notify(_('Ping: %d ok, %d auto-off, %d n/a').format(
		count(function(r) { return r.latency_ms != null && !r.auto_disabled; }),
		count(function(r) { return r.auto_disabled; }),
		count(function(r) { return r.na; })), 'info');
}

function commitForm(map) {
	return map.save().then(function() { return store.commit(); });
}

function fetchSub(map, sid, url) {
	return api.subscriptionUpdate(sid, url).then(function(res) {
		if (!(res && res.error === UNKNOWN_SUB))
			return res;
		return commitForm(map).then(function() { return api.subscriptionUpdate(sid, url); });
	});
}

function newId() {
	return 'sub_' + Math.random().toString(16).slice(2, 10);
}

return baseclass.extend({
	create: function(m, onPing) {
		var s = m.section(form.TypedSection, 'subscription', _('Subscriptions'),
			_('The selected subscription is used first; the others are a reserve. Switch it on the Dashboard.'));
		s.anonymous = true;
		s.addremove = true;
		s.addbtntitle = _('Add subscription');
		s.handleAdd = function() {
			var sid = this.map.data.add(CONFIG, 'subscription', newId());
			this.map.data.set(CONFIG, sid, 'name', _('Subscription') + ' ' + this.cfgsections().length);
			return this.map.save(null, true);
		};

		var name = s.option(form.Value, 'name', _('Name'));
		name.placeholder = subs.LEGACY_SUB;

		var url = s.option(form.Value, 'url', _('Subscription URL'),
			_('VPNON subscription link. Type it and press "Fetch subscription" — it is saved automatically when the fetch succeeds.'));
		url.password = true;

		var auto = s.option(form.Flag, 'auto_update', _('Auto-update'),
			_('Refresh the server list on a schedule.'));
		auto.default = '1';
		// rmempty=false обязателен: значение, совпавшее с default, LuCI удаляет из UCI на каждом
		// Save формы — и subupdate.sh читал бы пустоту вместо выбора пользователя.
		auto.rmempty = false;

		var interval = s.option(form.Value, 'update_interval', _('Interval (sec)'),
			_('How often to refresh the subscription. Values below 300 are clamped to 300.'));
		interval.depends('auto_update', '1');
		interval.datatype = 'uinteger';
		interval.default = '86400';
		interval.rmempty = false;
		// Выключенное автообновление прячет поле; без retain Save стёр бы заданный интервал,
		// и обратное включение молча вернуло бы сутки.
		interval.retain = true;

		var btn = s.option(form.Button, '_update', _('Update now'));
		btn.inputtitle = _('Fetch subscription');
		btn.inputstyle = 'apply';
		btn.onclick = function(ev, sid) {
			var typed = url.formvalue(sid) || '';
			if (typed === '') {
				notify(_('Enter a subscription URL first.'), 'warning');
				return Promise.resolve();
			}
			ui.showModal(_('Fetching subscription…'), [ E('p', { 'class': 'spinning' }, [ _('Contacting server') ]) ]);
			return fetchSub(m, sid, typed).then(function(res) {
				ui.hideModal();
				notifyFetch(res);
				if (!(res && res.error))
					window.setTimeout(function() { window.location.reload(); }, 600);
			}).catch(function(e) {
				ui.hideModal();
				notify(_('Fetch error: ') + e, 'error');
			});
		};

		var ping = s.option(form.DummyValue, '_ping', _('Latency'),
			_('Servers slower than 1 s or unreachable are skipped when connecting, until a later ping succeeds.'));
		ping.renderWidget = function(sid) {
			return icons.button('ping', _('Ping servers'), ui.createHandlerFn(this, function() {
				return api.subscriptionPing(sid).then(function(res) {
					notifyPing(res);
					if (!(res && res.error))
						onPing(res);
				}).catch(function(e) {
					notify(_('Ping failed: ') + e, 'error');
				});
			}));
		};
	}
});
